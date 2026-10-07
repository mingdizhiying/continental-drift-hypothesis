# 开发与贡献

使用 Node.js 24 LTS。项目无第三方 npm 运行依赖。

```sh
git clone https://github.com/mingdizhiying/continental-drift-hypothesis.git
cd continental-drift-hypothesis
git switch -c feat/your-change
npm start
```

完成一个范围清晰的改动后：

1. 更新 README 或策划案中的受影响规则，并在 CHANGELOG.md 的 Unreleased 部分记录变化。
2. 运行 npm test、npm run check 和 git diff --check。
3. 使用 feat:、fix:、docs:、test: 或 chore: 开头的提交说明，描述具体变化。
4. 推送功能分支并提交 PR，说明问题、修改后的行为、验证结果和已知限制。

不要提交 API 密钥、.env、运行日志或私人游戏记录。真实 AI 接口测试需要自行配置模型服务；未接入时应标注为本地模拟。版本号采用语义化版本格式，发布版本使用 v 前缀标签。

本仓库暂未指定开源许可证。GitHub 可见性与使用授权是不同事项。
