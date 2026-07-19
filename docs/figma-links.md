# Figma 输入

> 状态：占位。当前尚未选定 Demo 设计稿。

## 本地 MCP

仓库 `.mcp.json` 已配置 Figma Desktop 本地 MCP：`http://127.0.0.1:3845/mcp`。使用步骤：

1. 安装并打开 Figma Desktop，在桌面端打开目标设计文件。
2. 切换到 Dev Mode，在 Inspect 面板的 MCP Server 区域启用 Desktop MCP Server。
3. 启动 Claude Code，批准项目级 `figma` MCP Server。
4. 用 `claude mcp get figma` 或 `/mcp` 确认连接，再提供 Figma URL 或当前选中节点。

本模板有意使用本地 Desktop MCP。Figma 当前更推荐功能更完整的 Remote MCP；切换远程端点属于显式工程决策，不在任务执行中静默变更。官方配置说明见 [Figma Desktop MCP](https://developers.figma.com/docs/figma-mcp-server/local-server-installation/)。

本文件不维护与具体任务脱离的节点索引。选定 Figma Community 设计稿后，记录原始文件链接、作者、许可或使用说明、复制日期，以及 Demo 实际采用和主动偏离的范围。

具体节点链接进入对应任务卡；实现时按 `figma-to-flutter` Skill 读取当前节点，不从截图猜测不可见的交互或数据规则。
