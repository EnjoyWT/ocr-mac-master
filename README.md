# Mac-Master OCR 服务

基于 Apple Vision API 的分布式 OCR 识别服务主控端。

## 功能特性

✅ **集群管理** - 自动发现和管理 iOS Worker 节点  
✅ **负载均衡** - 智能选择最优处理设备  
✅ **故障转移** - 自动健康检查和恢复  
✅ **本地处理** - 无可用 Worker 时本地执行  
✅ **高性能** - 基于 Apple Vision 原生引擎

## 快速开始

```bash
# 启动服务
swift run

# 服务默认运行在 8080 端口
```

## API 接口

### 1. OCR 识别

```http
POST /api/v1/ocr
Content-Type: application/json

{
    "image": "base64_encoded_image_data",  // 必填，base64编码的图片数据
    "language": "zh-CN",                  // 可选，识别语言，默认支持中英文
    "recognitionLevel": "accurate",        // 可选，识别精度
    "confidence": 0.8                      // 可选，置信度阈值 0.0-1.0
}
```

**响应示例**:

```json
{
    "status": "success",
    "data": {
        "text": "识别的文本内容",
        "confidence": 0.95,
        "processingTime": 350,           // 处理时间(毫秒)
        "boundingBoxes": [               // 文本位置信息
            {
                "text": "文本片段",
                "confidence": 0.98,
                "x": 0.1,
                "y": 0.1,
                "width": 0.5,
                "height": 0.1
            }
        ]
    },
    "processedBy": "device-id"          // 处理设备标识
}
```

### 2. 集群状态

```http
GET /api/v1/status
```

**响应示例**:

```json
{
    "totalWorkers": 2,
    "healthyWorkers": 2,
    "localFallbackEnabled": true,
    "workers": [
        {
            "id": "device-1",
            "name": "iPhone 12",
            "host": "192.168.1.100",
            "port": 8080,
            "capabilities": ["vision"],
            "lastSeen": "2024-01-20 10:30:45",
            "isHealthy": true,
            "loadScore": 20,
            "averageResponseTime": 300,
            "successRate": 0.98,
            "recentFailures": 0,
            "totalRequests": 100,
            "successfulRequests": 98
        }
    ]
}
```

### 3. 健康检查

```http
GET /api/v1/health
```

**响应**: 返回 HTTP 200 表示服务正常

## 技术实现

- **Swift + Vapor**: 高性能 Web 服务框架
- **Vision Framework**: Apple 原生 OCR 引擎
- **Bonjour/mDNS**: 自动服务发现
- **HTTP/JSON**: 标准 API 协议

## 错误处理

- 图片数据无效: 400 Bad Request
- OCR 处理失败: 返回错误信息
- Worker 不可用: 自动切换到其他 Worker 或本地处理
- 网络超时: 配置了 5 秒连接超时和 30 秒读取超时