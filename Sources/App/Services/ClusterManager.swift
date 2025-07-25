//
//  ClusterManager.swift
//  ocr-cluster
//

import Foundation
import Logging
import Vapor

final class ClusterManager: ObservableObject {
    private let logger = Logger(label: "cluster-manager")
    
    private var bonjourService: BonjourService?

    private let localOCRService = VisionOCRService.shared
    private let httpClient: Client
    
    @Published var workers: [WorkerDevice] = []
    private var healthCheckTimer: Timer?
    
    init(client: Client) {
        self.httpClient = client
        setupBonjourService()
        setupObservers()
        startHealthCheck()
    }
    
    deinit {
        healthCheckTimer?.invalidate()
    }
    
    func setupBonjourService() {
        bonjourService = BonjourService()
        bonjourService?.startBrowsing()
    }

    // MARK: - OCR Processing

    func processOCR(request: OCRRequest) async throws -> OCRResponse {
        // 1. 尝试找到可用的worker
        if let worker = selectOptimalWorker() {
            logger.info("Dispatching to worker", metadata: ["workerId": "\(worker.id)"])
            
            do {
                let result = try await processOnWorker(worker: worker, request: request)
                return OCRResponse.success(data: result, processedBy: worker.id)
            } catch {
                logger.warning("Worker failed, falling back to local", metadata: [
                    "workerId": "\(worker.id)",
                    "error": "\(error)"
                ])
                
                // 标记worker为不健康
                markWorkerUnhealthy(worker.id)
            }
        }
        
        // 2. Fallback到本地处理
        logger.info("Processing locally (fallback)")
        return try await processLocally(request: request)
    }
    
    // MARK: - Worker Selection

    private func selectOptimalWorker() -> WorkerDevice? {
        let healthyWorkers = workers.filter { $0.isHealthy }
        
        guard !healthyWorkers.isEmpty else {
            logger.info("No healthy workers available")
            return nil
        }
        
        // 计算每个worker的综合得分
        return healthyWorkers.min { worker1, worker2 in
            // 基础负载分数 (0-100)
            let loadScore1 = Double(worker1.loadScore)
            let loadScore2 = Double(worker2.loadScore)
            
            // 响应时间权重 (0-50，越低越好)
            let responseTimeWeight1 = min(50.0, Double(worker1.averageResponseTime ?? 1000) / 20.0)
            let responseTimeWeight2 = min(50.0, Double(worker2.averageResponseTime ?? 1000) / 20.0)
            
            // 历史成功率权重 (0-30，越高越好)
            let successRateWeight1 = 30.0 * (1.0 - (Double(worker1.successRate ?? 1.0)))
            let successRateWeight2 = 30.0 * (1.0 - (Double(worker2.successRate ?? 1.0)))
            
            // 最近失败次数权重 (0-20，越低越好)
            let failureWeight1 = min(20.0, Double(worker1.recentFailures ?? 0) * 4.0)
            let failureWeight2 = min(20.0, Double(worker2.recentFailures ?? 0) * 4.0)
            
            // 计算总分 (越低越好)
            let totalScore1 = loadScore1 + responseTimeWeight1 + successRateWeight1 + failureWeight1
            let totalScore2 = loadScore2 + responseTimeWeight2 + successRateWeight2 + failureWeight2
            
            return totalScore1 < totalScore2
        }
    }
    
    // MARK: - Remote Processing

    private func processOnWorker(worker: WorkerDevice, request: OCRRequest) async throws -> OCRResponse.OCRData {
        let startTime = Date()
        let workerIndex = workers.firstIndex(where: { $0.id == worker.id })!
        
        do {
            let url = URI(string: "\(worker.endpoint)/ocr")
            
            let response = try await httpClient.post(url) { req in
                try req.content.encode(request)
                req.headers.add(name: .contentType, value: "application/json")
            }
            
            let ocrResponse = try response.content.decode(OCRResponse.self)
            
            guard let data = ocrResponse.data else {
                throw Abort(.internalServerError, reason: ocrResponse.error ?? "Worker returned no data")
            }
            
            // 更新性能指标
            DispatchQueue.main.async {
                let responseTime = Int(Date().timeIntervalSince(startTime) * 1000)
                self.updateWorkerMetrics(at: workerIndex, responseTime: responseTime, success: true)
            }
            
            return data
        } catch {
            // 更新失败指标
            DispatchQueue.main.async {
                self.updateWorkerMetrics(at: workerIndex, responseTime: nil, success: false)
            }
            throw error
        }
    }
    
    private func updateWorkerMetrics(at index: Int, responseTime: Int?, success: Bool) {
        // 更新总请求数
        workers[index].totalRequests = (workers[index].totalRequests ?? 0) + 1
        
        if success {
            // 更新成功请求数和成功率
            workers[index].successfulRequests = (workers[index].successfulRequests ?? 0) + 1
            workers[index].successRate = Double(workers[index].successfulRequests ?? 1) / Double(workers[index].totalRequests ?? 1)
            
            // 更新平均响应时间
            if let rt = responseTime {
                if let avgRT = workers[index].averageResponseTime {
                    workers[index].averageResponseTime = (avgRT + rt) / 2
                } else {
                    workers[index].averageResponseTime = rt
                }
            }
            
            // 重置失败计数
            workers[index].recentFailures = 0
        } else {
            // 更新失败计数和成功率
            workers[index].recentFailures = (workers[index].recentFailures ?? 0) + 1
            workers[index].successRate = Double(workers[index].successfulRequests ?? 0) / Double(workers[index].totalRequests ?? 1)
        }
    }
    
    // MARK: - Local Processing

    private func processLocally(request: OCRRequest) async throws -> OCRResponse {
        guard let imageBase64 = request.image,
              let imageData = Data(base64Encoded: imageBase64)
        else {
            throw Abort(.badRequest, reason: "Invalid image data")
        }
        
        let result = try await localOCRService.recognizeText(
            from: imageData,
            language: request.language,
            confidence: request.confidence
        )
        
        return OCRResponse.success(data: result, processedBy: "local-mac")
    }
    
    // MARK: - Health Management

    private func setupObservers() {
        // 监听Bonjour发现的workers
    
        DispatchQueue.main.async {
            self.bonjourService?.$discoveredWorkers
                .receive(on: DispatchQueue.main)
                .sink { [weak self] discoveredWorkers in
                    self?.updateWorkers(discoveredWorkers)
                }
                .store(in: &self.cancellables)
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func updateWorkers(_ newWorkers: [WorkerDevice]) {
        // 合并现有workers的状态和性能指标
        var updatedWorkers = newWorkers
        var newlyDiscovered: [WorkerDevice] = []
        for i in 0..<updatedWorkers.count {
            if let existingWorker = workers.first(where: { $0.id == updatedWorkers[i].id }) {
                // 保持现有状态
                updatedWorkers[i].isHealthy = existingWorker.isHealthy
                updatedWorkers[i].loadScore = existingWorker.loadScore
                // 保持性能指标
                updatedWorkers[i].averageResponseTime = existingWorker.averageResponseTime
                updatedWorkers[i].successRate = existingWorker.successRate
                updatedWorkers[i].recentFailures = existingWorker.recentFailures
                updatedWorkers[i].totalRequests = existingWorker.totalRequests
                updatedWorkers[i].successfulRequests = existingWorker.successfulRequests
            } else {
                // 新 worker
                newlyDiscovered.append(updatedWorkers[i])
            }
        }
        workers = updatedWorkers
        logger.info("Workers updated", metadata: [
            "total": "\(workers.count)",
            "healthy": "\(workers.filter { $0.isHealthy }.count)",
            "avgResponseTime": "\(workers.compactMap { $0.averageResponseTime }.reduce(0, +) / max(1, workers.count))ms"
        ])
        // 主动通知新 worker
        for worker in newlyDiscovered {
            Task {
                await self.notifyWorkerDiscovered(worker: worker)
            }
        }
    }
    
    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.performHealthCheck()
            }
        }
    }
    
    private func performHealthCheck() async {
        for i in 0..<workers.count {
            let isHealthy = await checkWorkerHealth(workers[i])
            
            DispatchQueue.main.async {
                self.workers[i].isHealthy = isHealthy
                // 使用 updateLastSeen 方法更新时间
                let localDate = Date()
                self.workers[i].updateLastSeen(localDate)
            }
        }
    }
    
    private func checkWorkerHealth(_ worker: WorkerDevice) async -> Bool {
        do {
            let url = URI(string: "\(worker.endpoint)/health")
            let response = try await httpClient.get(url)
            return response.status == .ok
        } catch {
            logger.warning("Health check failed", metadata: [
                "workerId": "\(worker.id)",
                "error": "\(error)"
            ])
            return false
        }
    }
    
    private func markWorkerUnhealthy(_ workerId: String) {
        DispatchQueue.main.async {
            if let index = self.workers.firstIndex(where: { $0.id == workerId }) {
                self.workers[index].isHealthy = false
            }
        }
    }
    
    // MARK: - Status

    func getClusterStatus() -> ClusterStatus {
        let totalWorkers = workers.count
        let healthyWorkers = workers.filter { $0.isHealthy }.count
        
        return ClusterStatus(
            totalWorkers: totalWorkers,
            healthyWorkers: healthyWorkers,
            localFallbackEnabled: true,
            workers: workers
        )
    }
    
    /// 主动通知 worker 已被 master 发现
    private func notifyWorkerDiscovered(worker: WorkerDevice) async {
        let url = URI(string: "\(worker.endpoint)/onDiscovered")
        do {
            let response = try await httpClient.post(url)
            if response.status == .ok {
                logger.info("成功通知 worker 已被发现", metadata: ["workerId": "\(worker.id)"])
            } else {
                logger.warning("通知 worker 失败", metadata: ["workerId": "\(worker.id)", "status": "\(response.status)"])
            }
        } catch {
            logger.error("通知 worker 异常", metadata: ["workerId": "\(worker.id)", "error": "\(error)"])
        }
    }
}

import Combine

// MARK: - Application Extension for ClusterManager

extension Application {
    private struct ClusterManagerKey: StorageKey {
        typealias Value = ClusterManager
    }

    var clusterManager: ClusterManager {
        get {
            if let existing = storage[ClusterManagerKey.self] {
                return existing
            } else {
                let new = ClusterManager(client: client)
                storage[ClusterManagerKey.self] = new
                return new
            }
        }
        set {
            storage[ClusterManagerKey.self] = newValue
        }
    }
}
