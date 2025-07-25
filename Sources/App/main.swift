//
//  main.swift
//  ocr-cluster
//
import Foundation

import Logging
import Vapor
//
//var env = try Environment.detect()
//try LoggingSystem.bootstrap(from: &env)
//
//let app =  Application(env)
//defer { app.shutdown() }
//
//try configure(app)
//
//// 启动信息
////app.logger.info("🚀 OCR Cluster starting...")
////app.logger.info("📡 Bonjour service discovery enabled")
////app.logger.info("🔄 Local fallback enabled")
////app.logger.info("🌐 Server will be available at: http://localhost:8080")
//
//try app.run()

private let logger = Logger(label: "main")

DispatchQueue.global(qos: .userInitiated).async {
    do {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app =  Application(env)
        defer { app.shutdown() }

        try configure(app)

        try app.run()

  
    } catch {
        
        logger.error("[错误] \(error.localizedDescription)")
    }
}

// 关键：保持主线程 RunLoop
RunLoop.main.run()
