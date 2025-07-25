//
//  BonjourService.swift
//  ocr-cluster
//

import Foundation
import Logging
import Network

final class BonjourService: NSObject, ObservableObject {
    static let serviceType = "_ocr._tcp."
    
    private let logger = Logger(label: "bonjour")
    private var browser: NetServiceBrowser?
    private var discoveredServices: [String: NetService] = [:]
    
    @Published var discoveredWorkers: [WorkerDevice] = []
    
    override init() {
        super.init()
    }
    
    deinit {
        stopBrowsing()
    }
    
    func startBrowsing() {
        logger.info("Starting Bonjour service discovery1")
        
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.schedule(in: .main, forMode: .default)
        browser?.searchForServices(ofType: Self.serviceType, inDomain: "local.")
    }
    
    func stopBrowsing() {
        logger.info("Stopping Bonjour service discovery")
        browser?.stop()
        browser = nil
        discoveredServices.removeAll()
        discoveredWorkers.removeAll()
    }
    
    private func addWorkerDevice(from service: NetService) {
        guard let addresses = service.addresses,
              !addresses.isEmpty
        else {
            logger.warning("Service has no addresses", metadata: ["name": "\(service.name)"])
            return
        }
        
        // 获取第一个可用的IPv4地址
//        guard let address = addresses.first,
//              let host = getHostFromAddress(address)
        guard let host = resolveUsableHost(from: addresses)
        else {
            logger.warning("Failed to extract host from service", metadata: ["name": "\(service.name)"])
            return
        }
        let localDate = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone.current
        let initialDate = formatter.date(from: formatter.string(from: localDate)) ?? localDate
        
        let worker = WorkerDevice(
            id: service.name,
            name: service.name,
            host: host,
            port: service.port,
            capabilities: ["vision"],
            lastSeen: initialDate,
            isHealthy: true,
            loadScore: 0,
            averageResponseTime: nil,
            successRate: nil,
            recentFailures: 0,
            totalRequests: 0,
            successfulRequests: 0
        )
        
        DispatchQueue.main.async {
            if let index = self.discoveredWorkers.firstIndex(where: { $0.id == worker.id }) {
                self.discoveredWorkers[index] = worker
            } else {
                self.discoveredWorkers.append(worker)
            }
        }
        
        logger.info("Added worker device", metadata: [
            "id": "\(worker.id)",
            "endpoint": "\(worker.endpoint)"
        ])
    }
    
    private func removeWorkerDevice(with name: String) {
        DispatchQueue.main.async {
            self.discoveredWorkers.removeAll { $0.id == name }
        }
        
        logger.info("Removed worker device", metadata: ["id": "\(name)"])
    }
    
    func getHostFromAddress(_ address: Data) -> String? {
        return address.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> String? in
            guard let sockaddrPointer = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                return nil
            }
            
            let family = sockaddrPointer.pointee.sa_family
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            
            if getnameinfo(sockaddrPointer,
                           socklen_t(address.count),
                           &hostBuffer,
                           socklen_t(hostBuffer.count),
                           nil,
                           0,
                           NI_NUMERICHOST) == 0
            {
                return String(cString: hostBuffer)
            } else {
                return nil
            }
        }
    }
    
    func resolveUsableHost(from addresses: [Data]) -> String? {
        for address in addresses {
            guard let host = address.withUnsafeBytes({ (pointer: UnsafeRawBufferPointer) -> String? in
                guard let sockaddrPointer = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                    return nil
                }
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sockaddrPointer,
                               socklen_t(address.count),
                               &hostBuffer,
                               socklen_t(hostBuffer.count),
                               nil,
                               0,
                               NI_NUMERICHOST) == 0
                {
                    return String(cString: hostBuffer)
                }
                return nil
            }) else {
                continue
            }
            
            // 跳过无效或本地回环地址
            if host == "0.0.0.0" || host == "::1" || host.hasPrefix("fe80") {
                continue
            }
            
            return host // 第一个可用 IPv4/IPv6
        }
        return nil
    }
}

// MARK: - NetServiceBrowserDelegate

extension BonjourService: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        logger.info("Found service", metadata: [
            "name": "\(service.name)",
            "type": "\(service.type)",
            "domain": "\(service.domain)"
        ])
        
        discoveredServices[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 10.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        logger.info("Service removed", metadata: ["name": "\(service.name)"])
        
        discoveredServices.removeValue(forKey: service.name)
        removeWorkerDevice(with: service.name)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        logger.error("Service browser failed to search", metadata: ["error": "\(errorDict)"])
    }
}

// MARK: - NetServiceDelegate

extension BonjourService: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        logger.info("Service resolved", metadata: [
            "name": "\(sender.name)",
            "port": "\(sender.port)"
        ])
        
        addWorkerDevice(from: sender)
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        logger.error("Failed to resolve service", metadata: [
            "name": "\(sender.name)",
            "error": "\(errorDict)"
        ])
    }
}
