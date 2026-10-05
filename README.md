# Sshwifty（1Panel 本地应用）

Web SSH / Telnet 客户端。以「配置文件 + 共享密钥 Preset」方式部署：把公钥分发到目标机器后，
在 Web UI 点击 Preset 即可免输入凭据连接。

## 文件

| 文件 | 说明 |
|---|---|
| `latest/docker-compose.yml` | 容器定义（`network_mode: host` + 两个只读挂载） |
| `latest/sshwifty.conf.json` | Sshwifty 配置（`Servers` / `Presets`） |
| `latest/gen-key.sh` | 生成或复用共享密钥（幂等，已存在则跳过） |
| `latest/up.sh` | 包装命令：先 `gen-key.sh`，再 `docker compose up -d` |
| `latest/ssh-keys/` | 密钥对。由 `gen-key.sh` 生成，已加入 `.gitignore`，不要提交 |

> 1Panel 安装时只渲染 `docker-compose.yml`、写 `.env`、复制 `data.yml`。
> 模板目录里的 `gen-key.sh` / `up.sh` / `ssh-keys/` **不会**被带到部署目录。

## ⚠️ 安装后必须补一步：生成密钥

1Panel 只做「渲染 compose → `docker compose up -d`」，**不会执行 `gen-key.sh`**。
安装刚完成时 `ssh-keys/` 是空的，配置里的 `file://` 取不到密钥，Sshwifty 会直接崩溃循环：

```
unable to parse Meta "Private Key": unable to open ...: no such file or directory
[ERR] Unable to start due to error: all existing redundant loader has failed
```

这是**预期现象**，不是配置写错。补上密钥即可恢复：

```sh
cd <部署目录>          # 1Panel 本地应用默认在 /opt/1panel/apps/local/<应用名>/<实例名>/

mkdir -p ssh-keys
ssh-keygen -t ed25519 -N '' -C sshwifty-shared -f ssh-keys/id_ed25519
chown 1000:1000 ssh-keys/id_ed25519 ssh-keys/id_ed25519.pub
chmod 600 ssh-keys/id_ed25519

docker compose up -d
```

启动正常的标志：

```
[INF] ... Configuration > Redundant: Loading configuration from: /etc/sshwifty/sshwifty.conf.json
[INF] ... Server (0.0.0.0:8182): Serving
```

在模板目录里也可以直接跑 `./up.sh`，它会先执行 `./gen-key.sh`。

## 分发公钥

把 `ssh-keys/id_ed25519.pub` 的内容追加到目标机器的 `~/.ssh/authorized_keys`。
重新生成密钥后旧公钥立即失效，需要重新分发。

## 约束

1. **容器以 uid 1000 运行**（镜像 `USER sshwifty`），挂载进去的文件必须对 uid 1000 可读：
   `sshwifty.conf.json` 与 `ssh-keys/id_ed25519` 都要 `chown 1000:1000` + `chmod 600`。
   多数编辑器与面板在改写文件后会重置为 `root:root` —— 内容没变但容器读不到，表现为突然启动失败，需重设 owner。
2. **设置 `SSHWIFTY_CONFIG` 后，所有 `SSHWIFTY_*` 环境变量都会被忽略**（源码是 if/else，不是叠加）。
   监听地址与端口只能写在 `sshwifty.conf.json` 的 `Servers[]` 里，compose 中的 `SSHWIFTY_LISTENPORT` 不再生效。
3. **配置加载没有回退**：文件缺失或格式错误 → 进程直接退出。
4. `/etc/sshwifty/sshwifty.conf.json` **不是**默认搜索路径（默认是 `/etc/sshwifty.conf.json`），
   能生效依赖 `SSHWIFTY_CONFIG` 指向它。

## Presets

`Presets[]` 每项为 `Title` / `Type` / `Host` / `TabColor` / `Meta`，其中 `Type` 需匹配命令名（`SSH` / `Telnet`）。
`Meta` 里出现的字段会以**只读**方式预填，未出现的字段留给用户手填。

```json
"Meta": {
  "User": "root",
  "Encoding": "utf-8",
  "Authentication": "Private Key",
  "Private Key": "file:///etc/sshwifty/keys/id_ed25519"
}
```

- `Meta` 的值支持 `literal://`（默认）、`file://`、`environment://` 三种 scheme，均在**启动时**解析一次。
- 只读不等于直连：点击 Preset 后**无需输入任何凭据**，但仍需点两次 —— 初始表单的 `Connect`
  与凭据框的 `Authenticate`。同一浏览器会话内凭据会被记住，重连时不再弹出。
- `Private Key` 字段在界面上是文件选择框。预设生效时它是 **disabled 的空框**，真实值在隐藏输入里，
  所以看上去像"要求提供密钥"，其实已经填好。认证失败时后端会重试并再次弹出该框。
- **已知限制**：`Host` 留空不会保持为空。服务端会用 `net.JoinHostPort(host, "22")` 补默认端口，
  空值变成 `":22"`，随后被客户端当作非空写回 `Meta`，使 Host 字段被锁成只读。
  因此每个 Preset 都必须写完整 `Host`，无法用空 Host 做"主机名自填"的通用模板。

## 🔴 安全

- `/sshwifty/socket/verify` **不需要任何认证**，Preset 的全部 `Meta`（**含私钥明文**）会下发给
  任何能访问该端口的人。这是上游既有设计，其 README 原文警告：`DO NOT add any secret information into Preset`。
- 拿到这把私钥等于拿到所有已授权机器的登录权。
- 缓解手段：设置 `SharedKey`、把 `Servers[0].ListenInterface` 改为 `127.0.0.1`，
  或在前端加一层带认证的反向代理。

## 密钥格式

`ssh-keygen -t ed25519` 产出的 `OPENSSH PRIVATE KEY` 格式可用（二进制中已链接 `parseOpenSSHPrivateKey`，
同时支持 PKCS#1 / PKCS#8 / EC）。密钥**不能带密码短语**。
