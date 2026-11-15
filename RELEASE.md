# AudioTag 发行指南

这份文档面向维护者，说明如何从源码构建 macOS 发行包。仓库中的源码和脚本不包含签名私钥、公证凭据或发布平台令牌；这些信息必须只保存在维护者本机的钥匙串或 CI Secret 中。

## 发行前检查

1. 确认项目源码、内置 Python 引擎和第三方组件的许可证已获准公开。
2. 确认 `Config/Release.json` 中的版本号、构建号、HTTPS 更新源和 Sparkle 公钥属于本次发行。
3. 准备 Apple Developer ID 证书、公证配置和 Sparkle Ed25519 私钥。私钥只放在本机钥匙串，不要导出到仓库、网站或日志。
4. 将对应版本的第三方源码和许可证放入 `site/sources/`；发行包不能替代对应源码归档。
5. 在干净环境中运行测试，并确认待发布的应用不是本地调试包。

## 本地构建

开发构建只需要 Xcode Command Line Tools、`uv` 和本机 FFmpeg：

```sh
./script/build_and_run.sh --build-only
swift test
.venv/bin/python -m pytest -q
node --test tests/site.test.cjs tests/local_editor.test.cjs
```

正式发行还需要 FFmpeg 与 LAME 的校验源码。仓库的 `site/sources/` 已提供对应归档；脚本会在缺少本地副本时自动复制到 `.build/release-tools/`：

```sh
bash script/build_release_tools.sh
```

## 本地公证发行

为避免误用维护者身份，发行脚本要求显式提供签名身份、公证配置和 Sparkle 钥匙串账户：

```sh
SIGNING_IDENTITY='Developer ID Application: <维护者>' \
NOTARY_PROFILE='<notarytool 配置名>' \
SPARKLE_KEY_ACCOUNT='<Sparkle 私钥账户名>' \
bash script/prepare_release.sh
```

脚本会测试、构建、签名、公证、装订票据并生成发行文件。`script/package_dmg.sh` 负责生成带 `Applications` 快捷方式的 DMG；`script/sign_macos_app.sh` 会按 Sparkle 的 XPC、Updater 和框架顺序签名嵌套代码。只有确认 Apple 公证通过、签名有效、下载地址正确且对应源码归档齐全后，才能发布网站和更新源。

本地 DMG 打包需要先准备 `.venv/bin/pyinstaller`、Developer ID 证书、公证配置和 Sparkle 私钥账户：

```sh
SIGNING_IDENTITY='Developer ID Application: <维护者>' \
DIST_DIR="$PWD/dist/release" \
bash script/package_dmg.sh 1.0.0
```

随后使用 `xcrun notarytool submit` 提交 `dist/release/AudioTag-v1.0.0-macOS-arm64.dmg`，状态为 `Accepted` 后执行 `xcrun stapler staple`、`xcrun stapler validate` 和 `spctl --assess`。已有的 `script/prepare_release.sh` 仍适合使用钥匙串中的 `NOTARY_PROFILE` 完成 ZIP 应用公证和官网文件生成。

## GitHub Actions 公证发行

仓库中的 `.github/workflows/release-dmg.yml` 提供参考 `ZhiziTime` 的一键流程：校验版本、在 Apple Silicon runner 上构建 DMG、导入 Developer ID 证书、使用 App Store Connect API Key 公证并装订票据、用 Sparkle Ed25519 私钥生成带签名的 appcast，最后创建 GitHub Release。

在仓库 Settings → Secrets and variables → Actions 中配置以下 Secrets：

- `DEVELOPER_ID_CERTIFICATE_BASE64`、`DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_API_KEY_P8_BASE64`、`APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID`
- `SPARKLE_EDDSA_PRIVATE_KEY`

私钥只放在 macOS 钥匙串或 GitHub Secret。使用 `script/configure_sparkle_keys.sh setup` 生成或核对公钥；不要把私钥写入仓库。手动运行 workflow 时，版本必须与 `Config/Release.json` 的 `version` 一致。workflow 生成的 `appcast.xml` 需要同步到官网的 `updates/appcast.xml`，下载地址使用 GitHub Release 的版本化制品地址。

```sh
python3 script/release_check.py
python3 script/check_site.py
```

仅检查网站草稿时使用 `--draft`；草稿检查通过不代表可以公开发行。发布时只上传 `site/` 中已审核的静态文件，保留历史版本，不覆盖已经公开的同版本制品。

## 版本更新

增加版本号或构建号后重新构建。不要修改已经公开的 ZIP、校验值、appcast 签名或历史发行说明。更新 Sparkle 公钥、Bundle ID 或更新源会使已有安装无法验证后续更新，必须单独规划迁移。
