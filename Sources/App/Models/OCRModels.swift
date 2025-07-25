//
//  OCRModels.swift
//  ocr-cluster
//

import Foundation
import Vapor

// MARK: - API Models
struct OCRRequest: Content {
    let image: String?           // base64编码的图片数据
    let language: String?
    let recognitionLevel: String?
    let confidence: Float?
}

struct OCRResponse: Content {
    let status: String
    let data: OCRData?
    let error: String?
    let processedBy: String?     // 新增：处理设备标识

    struct OCRData: Content {
        let text: String
        let confidence: Float
        let processingTime: Int  // milliseconds
        let boundingBoxes: [BoundingBox]?
    }

    struct BoundingBox: Content {
        let text: String
        let confidence: Float
        let x: Float
        let y: Float
        let width: Float
        let height: Float
    }
}

extension OCRResponse {
    static func success(data: OCRData, processedBy: String = "local") -> OCRResponse {
        return OCRResponse(status: "success", data: data, error: nil, processedBy: processedBy)
    }

    static func failure(error: String) -> OCRResponse {
        return OCRResponse(status: "error", data: nil, error: error, processedBy: nil)
    }
}

// MARK: - Cluster Models
struct WorkerDevice: Codable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let capabilities: [String]
    private(set) var lastSeen: Date
    var isHealthy: Bool
    var loadScore: Int           // 负载评分 (0-100)
    var averageResponseTime: Int? // 平均响应时间（毫秒）
    var successRate: Double?      // 成功率 (0.0-1.0)
    var recentFailures: Int?      // 最近失败次数
    var totalRequests: Int?       // 总请求数
    var successfulRequests: Int?  // 成功请求数
    
    var endpoint: String {
        return "http://\(host):\(port)"
    }
    
    // 添加自定义初始化器
    init(id: String, name: String, host: String, port: Int, capabilities: [String], lastSeen: Date, isHealthy: Bool, loadScore: Int, averageResponseTime: Int? = nil, successRate: Double? = nil, recentFailures: Int? = nil, totalRequests: Int? = nil, successfulRequests: Int? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.capabilities = capabilities
        self.lastSeen = lastSeen
        self.isHealthy = isHealthy
        self.loadScore = loadScore
        self.averageResponseTime = averageResponseTime
        self.successRate = successRate
        self.recentFailures = recentFailures
        self.totalRequests = totalRequests
        self.successfulRequests = successfulRequests
    }
    
    // 添加 CodingKeys 枚举
    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, capabilities, lastSeen, isHealthy
        case loadScore, averageResponseTime, successRate, recentFailures
        case totalRequests, successfulRequests
    }
    
    // 自定义编码器
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(isHealthy, forKey: .isHealthy)
        try container.encode(loadScore, forKey: .loadScore)
        try container.encode(averageResponseTime, forKey: .averageResponseTime)
        try container.encode(successRate, forKey: .successRate)
        try container.encode(recentFailures, forKey: .recentFailures)
        try container.encode(totalRequests, forKey: .totalRequests)
        try container.encode(successfulRequests, forKey: .successfulRequests)
        
        // 使用 DateFormatter 格式化时间
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: lastSeen)
        try container.encode(dateString, forKey: .lastSeen)
    }
    
    // 自定义解码器
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        capabilities = try container.decode([String].self, forKey: .capabilities)
        isHealthy = try container.decode(Bool.self, forKey: .isHealthy)
        loadScore = try container.decode(Int.self, forKey: .loadScore)
        averageResponseTime = try container.decodeIfPresent(Int.self, forKey: .averageResponseTime)
        successRate = try container.decodeIfPresent(Double.self, forKey: .successRate)
        recentFailures = try container.decodeIfPresent(Int.self, forKey: .recentFailures)
        totalRequests = try container.decodeIfPresent(Int.self, forKey: .totalRequests)
        successfulRequests = try container.decodeIfPresent(Int.self, forKey: .successfulRequests)
        
        // 使用 DateFormatter 解析时间
        let dateString = try container.decode(String.self, forKey: .lastSeen)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        if let date = formatter.date(from: dateString) {
            lastSeen = date
        } else {
            lastSeen = Date()
        }
    }
    
    // 提供修改 lastSeen 的方法
    mutating func updateLastSeen(_ date: Date) {
        lastSeen = date
    }
}

struct ClusterStatus: Content {
    let totalWorkers: Int
    let healthyWorkers: Int
    let localFallbackEnabled: Bool
    let workers: [WorkerDevice]
}