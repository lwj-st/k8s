## 脚本说明

- 自动检测是否存在 tmp-shell Pod；
- 若不存在则创建（使用你指定的镜像）；
- 自动等待 Pod 就绪；
- 获取所有 Service 域名 + 端口；
- 将数据和测试脚本上传进 Pod；
- 在 Pod 内执行网络连通性测试；
- 执行完自动删除 Pod（--rm 模式）。
- 支持设置 DNS和TCP白名单，因为有些不通是正常现象



## 使用方法

```bash
curl -sSL https://raw.githubusercontent.com/lwj-st/k8s/main/test/k8s-network-tcp-dns-check.sh | bash

🚀 启动临时调试 Pod [tmp-shell]...
pod/tmp-shell created
⏳ 等待 Pod 启动中...
pod/tmp-shell condition met
📡 获取所有 Service 域名和端口...
✅ 已生成 targets.txt
...
📤 上传目标文件和脚本...
🧪 开始在 Pod 内执行测试...
开始测试 DNS + TCP 连接...
--------------------------------------
[TCP FAIL] lazyllm-service.lazyllm-platform-ci.svc.cluster.local:8080 无法连接
--------------------------------------
测试完成 ✅
🧹 删除临时 Pod...
pod "tmp-shell" deleted
✅ 全部完成！
```

## 手动验证
```bash
kubectl run tmp-shell --rm -i --tty --image=registry.cn-hangzhou.aliyuncs.com/liwenjian123/netshoot:v0.14 -- /bin/bash
```

