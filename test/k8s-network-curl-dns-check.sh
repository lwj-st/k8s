#!/bin/bash
set -e

# ============================
# ⚙️ 基本配置
# ============================
POD_NAME="tmp-shell"
NAMESPACE="default"
IMAGE="registry.cn-hangzhou.aliyuncs.com/liwenjian123/netshoot:v0.14"
# IMAGE="nicolaka/netshoot:v0.14"
LOCAL_TARGETS="targets.txt"
LOCAL_SCRIPT="test_network.sh"
TARGET_FILE="/tmp/targets.txt"
SCRIPT_FILE="/tmp/test_network.sh"
# ============================

echo "🚀 启动临时调试 Pod [$POD_NAME]..."

# 检查是否已有相同 pod 存在
if kubectl get pod -n "$NAMESPACE" "$POD_NAME" &>/dev/null; then
  echo "⚠️ Pod 已存在，跳过创建"
else
  kubectl run "$POD_NAME" -n "$NAMESPACE" --image="$IMAGE" --restart=Never -- sleep infinity
  echo "⏳ 等待 Pod 启动中..."
  kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=60s
fi

# ============================
# 🧾 生成 service 目标列表
# ============================
echo "📡 获取所有 Service 域名和端口..."
kubectl get svc -A -o json | jq -r '
  .items[] |
  .metadata.namespace as $ns |
  .metadata.name as $name |
  .spec.ports[] |
  "\($name).\($ns).svc.cluster.local:\(.port)"
' | sort -u > "$LOCAL_TARGETS"

echo "✅ 已生成 $LOCAL_TARGETS"
head -n 5 "$LOCAL_TARGETS"
echo "..."

# ============================
# 🧰 生成测试脚本
# ============================
cat > "$LOCAL_SCRIPT" <<'EOF'
#!/bin/bash
input_file="/tmp/targets.txt"

# 白名单定义（DNS和TCP都适用）
DNS_WHITELIST=(
  "kubelet.kube-system.svc.cluster.local"
)
TCP_WHITELIST=(
  "istio-ingressgateway.istio-system.svc.cluster.local:443"
  "istio-ingressgateway.istio-system.svc.cluster.local:80"
  "kubelet.kube-system.svc.cluster.local:10255"
  "kubelet.kube-system.svc.cluster.local:4194"
)

in_whitelist() {
  local target="$1"
  shift
  local list=("$@")
  for item in "${list[@]}"; do
    [[ "$target" == "$item" ]] && return 0
  done
  return 1
}

echo "开始测试 DNS + TCP 连接..."
echo "--------------------------------------"

while read -r line; do
  [[ -z "$line" ]] && continue
  host=$(echo "$line" | cut -d':' -f1)
  port=$(echo "$line" | cut -d':' -f2)
  target="${host}:${port}"

  # DNS 检查
  nslookup  "$host" > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    if in_whitelist "$host" "${DNS_WHITELIST[@]}"; then
      echo "[DNS IGNORE] $host 在白名单中"
    else
      echo "[DNS FAIL] $host 无法解析"
    fi
    continue
  fi

  # TCP 检查
  timeout 3 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null
  if [[ $? -ne 0 ]]; then
    if ! in_whitelist "$target" "${TCP_WHITELIST[@]}"; then
      #echo "[TCP IGNORE] $target 在白名单中"
    #else
      echo "[TCP FAIL] $target 无法连接"
    fi
  #else
  #  echo "[TCP OK] $target"
  fi
done < "$input_file"

echo "--------------------------------------"
echo "测试完成 ✅"
EOF

# ============================
# 📤 上传并执行测试
# ============================
echo "📤 上传目标文件和脚本..."
kubectl cp "$LOCAL_TARGETS" "$NAMESPACE/$POD_NAME:$TARGET_FILE"
kubectl cp "$LOCAL_SCRIPT" "$NAMESPACE/$POD_NAME:$SCRIPT_FILE"

echo "🧪 开始在 Pod 内执行测试..."
kubectl exec -it -n "$NAMESPACE" "$POD_NAME" -- bash -c "chmod +x $SCRIPT_FILE && $SCRIPT_FILE"

# ============================
# 🧹 清理临时 Pod
# ============================
echo "🧹 删除临时 Pod..."
kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --ignore-not-found

echo "✅ 全部完成！"
