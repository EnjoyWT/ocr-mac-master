//
//  OCRController.swift
//  ocr-cluster
//

import Logging
import Vapor

struct OCRController: RouteCollection {
    private let logger = Logger(label: "ocr-controller")
    
    func boot(routes: RoutesBuilder) throws {
        let ocr = routes.grouped("api", "v1")
        
        ocr.post("ocr", use: processOCR)
        ocr.get("status", use: getStatus)
        ocr.get("health", use: health)
    }
    
    func processOCR(req: Request) async throws -> OCRResponse {
        logger.info("Received OCR request", metadata: [
            "clientIP": "\(req.remoteAddress?.description ?? "unknown")"
        ])
        
        let ocrRequest = try req.content.decode(OCRRequest.self)
        
        // 验证请求
        guard ocrRequest.image != nil else {
            logger.warning("Invalid request: missing image data")
            throw Abort(.badRequest, reason: "Image data is required")
        }
        
        // 获取ClusterManager并处理请求
        let clusterManager = req.application.clusterManager
        
        do {
            let startTime = Date()
            let response = try await clusterManager.processOCR(request: ocrRequest)
            let processingTime = Date().timeIntervalSince(startTime)
            
            logger.info("OCR request completed", metadata: [
                "processingTime": "\(Int(processingTime * 1000))ms",
                "processedBy": "\(response.processedBy ?? "unknown")",
                "success": "\(response.status == "success")"
            ])
            
            return response
        } catch {
            logger.error("OCR processing failed", metadata: ["error": "\(error)"])
            return OCRResponse.failure(error: error.localizedDescription)
        }
    }
    
    func getStatus(req: Request) async throws -> ClusterStatus {
        let clusterManager = req.application.clusterManager
        return clusterManager.getClusterStatus()
    }
    
    func health(req: Request) async throws -> [String: String] {
        return ["status": "ok"]
    }
}
