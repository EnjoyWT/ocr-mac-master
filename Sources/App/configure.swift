//
//  configure.swift
//  ocr-cluster
//

import Vapor
import Logging

public func configure(_ app: Application) throws {
    // 配置日志
    app.logger.logLevel = .info
    
    // 注册服务
    app.clusterManager = ClusterManager(client: app.client)
    
    // 注册路由
    try app.register(collection: OCRController())
    
    // 配置中间件
    app.middleware.use(CORSMiddleware(configuration: .init(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith]
    )))
    
    // 配置HTTP客户端
    app.http.client.configuration.timeout = HTTPClient.Configuration.Timeout(
        connect: .seconds(5),
        read: .seconds(30)
    )
    
    app.logger.info("OCR Cluster service configured successfully")
}