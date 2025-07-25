//
//  VisionOCRService.swift
//  ocr-cluster
//

import AppKit
import CoreGraphics
import Foundation
import Vision
import Logging

final class VisionOCRService: Sendable {
    enum OCRError: Error {
        case invalidImageData
        case recognitionFailed
        case noTextFound
    }
    
    static let shared = VisionOCRService()
    private let logger = Logger(label: "vision-ocr")
    
    private init() {}
    
    func recognizeText(from imageData: Data, language: String? = nil, confidence: Float? = nil) async throws -> OCRResponse.OCRData {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        logger.info("Starting local OCR processing", metadata: [
            "imageSize": "\(imageData.count)",
            "language": "\(language ?? "auto")"
        ])
        
        // 创建图像
        guard let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            logger.error("Failed to create CGImage from data")
            throw OCRError.invalidImageData
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    self.logger.error("Vision request failed", metadata: ["error": "\(error)"])
                    continuation.resume(throwing: error)
                    return
                }
                
                let endTime = CFAbsoluteTimeGetCurrent()
                let processingTime = Int((endTime - startTime) * 1000)
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    self.logger.error("No recognition results")
                    continuation.resume(throwing: OCRError.recognitionFailed)
                    return
                }
                
                if observations.isEmpty {
                    self.logger.warning("No text found in image")
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }
                
                let boundingBoxes = observations.compactMap { observation -> OCRResponse.BoundingBox? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let boundingBox = observation.boundingBox
                    return OCRResponse.BoundingBox(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        x: Float(boundingBox.origin.x),
                        y: Float(boundingBox.origin.y),
                        width: Float(boundingBox.width),
                        height: Float(boundingBox.height)
                    )
                }
                
                // 过滤置信度
                let filteredBoxes: [OCRResponse.BoundingBox]
                if let threshold = confidence {
                    filteredBoxes = boundingBoxes.filter { $0.confidence >= threshold }
                } else {
                    filteredBoxes = boundingBoxes
                }
                
                let allText = filteredBoxes.map { $0.text }.joined(separator: "\n")
                let averageConfidence = filteredBoxes.isEmpty ? 0.0 : (filteredBoxes.reduce(0.0) { $0 + $1.confidence } / Float(filteredBoxes.count))
                
                self.logger.info("OCR processing completed", metadata: [
                    "processingTime": "\(processingTime)ms",
                    "textLength": "\(allText.count)",
                    "confidence": "\(averageConfidence)",
                    "boundingBoxes": "\(filteredBoxes.count)"
                ])
                
                let result = OCRResponse.OCRData(
                    text: allText,
                    confidence: averageConfidence,
                    processingTime: processingTime,
                    boundingBoxes: filteredBoxes
                )
                continuation.resume(returning: result)
            }
            
            // 配置识别请求
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            // 设置语言（如果提供）
            if let language = language {
                request.recognitionLanguages = [language]
            } else {
                request.recognitionLanguages = ["zh-CN", "en-US"]
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                self.logger.error("Failed to perform Vision request", metadata: ["error": "\(error)"])
                continuation.resume(throwing: error)
            }
        }
    }
}