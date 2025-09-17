# TiDB集群故障排查命令手册

## 镜像查看
ctr -n k8s.io images list

## 域名解释

在集群内部的pod里可以使用 nslookup 命令验证是否能解析到pod地址
```bash
basic-pd-0.basic-pd-peer.tidb-cluster.svc 分解：

1. basic-pd-0：StatefulSet 创建的 Pod 序号为 0 的实例。
2. basic-pd-peer：这是 PD 组件的 Headless Service，用来给每个 Pod 建立唯一 DNS 记录。也是svc名
3. tidb-cluster：命名空间。
4. svc：说明这是一个 Service。
```



## 日志分析总结

从日志中可以看出主要问题：
1. **DNS解析超时**：`lookup basic-pd-0.basic-pd-peer.tidb-cluster.svc: i/o timeout`
2. **etcd集群无leader**：`etcdserver: no leader`
3. **网络连接问题**：`connection reset by peer`
4. **TiDB实例无法连接**：`no alive TiDB instance`

## 网络排查命令

### 1. DNS解析排查
```bash
# 检查DNS解析

nslookup basic-pd-0.basic-pd-peer.tidb-cluster.svc.cluster.local
nslookup basic-pd-1.basic-pd-peer.tidb-cluster.svc.cluster.local

# 检查CoreDNS状态
kubectl get pods -n kube-system | grep coredns
kubectl logs -n kube-system -l k8s-app=kube-dns

# 检查DNS配置
kubectl get svc -n kube-system kube-dns
kubectl describe svc -n kube-system kube-dns
```

### 2. 网络连通性测试
```bash
# 测试Pod间网络连通性
kubectl exec -n tidb-cluster basic-pd-0 -- ping basic-pd-1.basic-pd-peer.tidb-cluster.svc
kubectl exec -n tidb-cluster basic-pd-0 -- telnet basic-pd-1.basic-pd-peer.tidb-cluster.svc 2379
kubectl exec -n tidb-cluster basic-pd-0 -- nslookup basic-pd-0.basic-pd-peer.tidb-cluster.svc

# 检查网络策略
kubectl get networkpolicy -n tidb-cluster
kubectl describe networkpolicy -n tidb-cluster

# 检查服务端点
kubectl get endpoints -n tidb-cluster
kubectl describe endpoints -n tidb-cluster basic-pd-peer
```

### 3. 端口和服务检查
```bash
# 检查服务状态
kubectl get svc -n tidb-cluster
kubectl describe svc -n tidb-cluster basic-pd-peer

# 检查端口监听
kubectl exec -n tidb-cluster basic-pd-0 -- netstat -tlnp
kubectl exec -n tidb-cluster basic-pd-1 -- netstat -tlnp

# 检查防火墙规则
kubectl exec -n tidb-cluster basic-pd-0 -- iptables -L
```

## Kubernetes资源排查命令

### 1. Pod状态检查
```bash
# 检查Pod状态
kubectl get pods -n tidb-cluster -o wide
kubectl describe pods -n tidb-cluster

# 检查Pod日志
kubectl logs -n tidb-cluster basic-pd-0 --tail=100
kubectl logs -n tidb-cluster basic-pd-1 --tail=100

# 检查Pod事件
kubectl get events -n tidb-cluster --sort-by='.lastTimestamp'
```

### 2. 配置和资源检查
```bash
# 检查YAML配置
kubectl get -n tidb-cluster -o yaml statefulset basic-pd
kubectl get -n tidb-cluster -o yaml configmap

# 检查资源限制
kubectl top pods -n tidb-cluster
kubectl describe nodes

# 检查存储
kubectl get pv,pvc -n tidb-cluster
kubectl describe pvc -n tidb-cluster
```

## etcd集群排查命令

### 1. etcd健康检查
```bash
# 检查etcd集群状态
kubectl exec -n tidb-cluster basic-pd-0 -- etcdctl --endpoints=http://localhost:2379 endpoint health
kubectl exec -n tidb-cluster basic-pd-1 -- etcdctl --endpoints=http://localhost:2379 endpoint health

# 检查etcd成员
kubectl exec -n tidb-cluster basic-pd-0 -- etcdctl --endpoints=http://localhost:2379 member list
kubectl exec -n tidb-cluster basic-pd-1 -- etcdctl --endpoints=http://localhost:2379 member list

# 检查etcd集群状态
kubectl exec -n tidb-cluster basic-pd-0 -- etcdctl --endpoints=http://localhost:2379 cluster-health
```

### 2. etcd配置检查
```bash
# 检查etcd配置
kubectl exec -n tidb-cluster basic-pd-0 -- cat /etc/pd/pd.toml
kubectl exec -n tidb-cluster basic-pd-1 -- cat /etc/pd/pd.toml

# 检查etcd数据目录
kubectl exec -n tidb-cluster basic-pd-0 -- ls -la /var/lib/pd/
kubectl exec -n tidb-cluster basic-pd-1 -- ls -la /var/lib/pd/
```

## TiDB集群排查命令

### 1. TiDB组件状态
```bash
# 检查所有TiDB组件
kubectl get pods -n tidb-cluster -l app.kubernetes.io/component=pd
kubectl get pods -n tidb-cluster -l app.kubernetes.io/component=tidb
kubectl get pods -n tidb-cluster -l app.kubernetes.io/component=tikv

# 检查TiDB服务
kubectl get svc -n tidb-cluster
kubectl describe svc -n tidb-cluster
```

### 2. TiDB集群信息
```bash
# 使用PD API检查集群状态
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/cluster
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/stores
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/regions
```

## 系统资源排查命令

### 1. 系统资源检查
```bash
# 检查节点资源
kubectl top nodes
kubectl describe nodes

# 检查Pod资源使用
kubectl top pods -n tidb-cluster
kubectl describe pods -n tidb-cluster

# 检查磁盘空间
kubectl exec -n tidb-cluster basic-pd-0 -- df -h
kubectl exec -n tidb-cluster basic-pd-1 -- df -h
```

### 2. 系统日志检查
```bash
# 检查系统日志
kubectl exec -n tidb-cluster basic-pd-0 -- journalctl -u kubelet
kubectl exec -n tidb-cluster basic-pd-0 -- dmesg | tail -50

# 检查容器运行时日志
kubectl logs -n tidb-cluster basic-pd-0 -c basic-pd --previous
```

## 修复建议

### 1. 立即修复步骤
```bash
# 重启有问题的Pod
kubectl delete pod -n tidb-cluster basic-pd-0
kubectl delete pod -n tidb-cluster basic-pd-1

# 检查Pod重新创建状态
kubectl get pods -n tidb-cluster -w
```

### 2. 配置修复
```bash
# 检查并修复DNS配置
kubectl get configmap -n kube-system coredns -o yaml

# 检查网络插件状态
kubectl get pods -n kube-system | grep -E "(calico|flannel|weave)"
```

### 3. 数据恢复
```bash
# 备份etcd数据
kubectl exec -n tidb-cluster basic-pd-0 -- tar -czf /tmp/pd-backup.tar.gz /var/lib/pd/

# 检查数据一致性
kubectl exec -n tidb-cluster basic-pd-0 -- etcdctl --endpoints=http://localhost:2379 get / --prefix --keys-only
```

## 高级排查命令

### 1. 网络深度排查
```bash
# 使用tcpdump抓包分析
kubectl exec -n tidb-cluster basic-pd-0 -- tcpdump -i any -n port 2379

# 检查网络延迟
kubectl exec -n tidb-cluster basic-pd-0 -- ping -c 10 basic-pd-1.basic-pd-peer.tidb-cluster.svc

# 检查网络路由
kubectl exec -n tidb-cluster basic-pd-0 -- ip route
kubectl exec -n tidb-cluster basic-pd-0 -- ip addr show
```

### 2. 性能分析
```bash
# 检查CPU和内存使用
kubectl exec -n tidb-cluster basic-pd-0 -- top
kubectl exec -n tidb-cluster basic-pd-0 -- free -h

# 检查磁盘IO
kubectl exec -n tidb-cluster basic-pd-0 -- iostat -x 1 5

# 检查网络统计
kubectl exec -n tidb-cluster basic-pd-0 -- netstat -i
kubectl exec -n tidb-cluster basic-pd-0 -- ss -tuln
```

### 3. 集群状态详细检查
```bash
# 检查集群版本
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/version

# 检查调度器状态
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/schedulers

# 检查热点区域
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/hotspot/regions/read

# 检查集群配置
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/config
```

## 故障恢复流程

### 1. 紧急恢复
```bash
# 1. 停止所有PD实例
kubectl scale statefulset basic-pd --replicas=0 -n tidb-cluster

# 2. 清理有问题的Pod
kubectl delete pod -n tidb-cluster basic-pd-0 basic-pd-1

# 3. 重新启动PD
kubectl scale statefulset basic-pd --replicas=2 -n tidb-cluster

# 4. 监控启动过程
kubectl get pods -n tidb-cluster -w
```

### 2. 数据一致性检查
```bash
# 检查etcd数据完整性
kubectl exec -n tidb-cluster basic-pd-0 -- etcdctl --endpoints=http://localhost:2379 endpoint status --write-out=table

# 检查集群健康状态
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/health

# 检查所有存储节点
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/stores
```

### 3. 服务恢复验证
```bash
# 验证PD服务可用性
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/status

# 验证TiDB连接
kubectl exec -n tidb-cluster basic-pd-0 -- curl http://localhost:2379/pd/api/v1/cluster

# 检查所有组件状态
kubectl get all -n tidb-cluster
```

## 预防措施

### 1. 监控设置
```bash
# 设置资源监控
kubectl top pods -n tidb-cluster --containers

# 设置日志监控
kubectl logs -n tidb-cluster -l app.kubernetes.io/component=pd --tail=0 -f

# 设置事件监控
kubectl get events -n tidb-cluster --watch
```

### 2. 定期检查
```bash
# 每日健康检查脚本
#!/bin/bash
kubectl get pods -n tidb-cluster
kubectl exec -n tidb-cluster basic-pd-0 -- curl -s http://localhost:2379/pd/api/v1/health
kubectl exec -n tidb-cluster basic-pd-0 -- etcdctl --endpoints=http://localhost:2379 endpoint health
```

### 3. 备份策略
```bash
# 定期备份etcd数据
kubectl exec -n tidb-cluster basic-pd-0 -- etcdctl --endpoints=http://localhost:2379 snapshot save /tmp/etcd-backup.db

# 备份PD配置
kubectl get configmap -n tidb-cluster -o yaml > pd-config-backup.yaml
```

---

**注意**: 执行这些命令时请确保有适当的权限，并在生产环境中谨慎操作。建议先在测试环境中验证命令的有效性。
