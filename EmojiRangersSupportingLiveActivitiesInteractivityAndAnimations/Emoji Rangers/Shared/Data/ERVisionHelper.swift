//
//  ERVisionHelper.swift
//  Wrenda
//
//  Created by Gavin Xiang on 10/10/25.
//  Copyright © 2025 PlanetArt. All rights reserved.
//

import Vision
import Photos
import UIKit
import Foundation

// Actor for processing state management
@available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, *)
internal actor ProcessingState {
    private var isProcessing = false
    
    func startProcessing() -> Bool {
        if isProcessing {
            return false // Already processing
        }
        isProcessing = true
        return true // Can start processing
    }
    
    func finishProcessing() {
        isProcessing = false
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, *)
public actor ERVisionHelper {
    
    // Singleton instance
    public static let shared = ERVisionHelper()
    
    // Actor-based state management
    private let processingState = ProcessingState()
    
    private init() {
        // Actor initialization
    }
    
    // MARK: - Vision Analysis
    func calculateAestheticsScore(image: UIImage) async throws -> ImageAestheticsScoresObservation? {
        // Convert UIImage to CIImage
        guard let ciImage = CIImage(image: image) else { return nil }
        
        // Set up the calculate image aesthetics scores request
        let request = CalculateImageAestheticsScoresRequest()
        
        // Perform the request
        return try await request.perform(on: ciImage)
    }
    
    /// A Boolean value that represents images that are not necessarily of poor image quality, but may not have memorable or exciting content.
    func isUtility(image: UIImage) async -> Bool {
        do {
            async let aestheticsTask = calculateAestheticsScore(image: image)
            let observation = try await aestheticsTask
            var isUtility = false
            if observation?.isUtility == true {
                isUtility = true
            }
            return isUtility
        } catch {
            // print("[BestPhoto]  Vision analysis failed: \(error)")
            return false
        }
    }
    
    nonisolated private func getAvailableMemoryInGB() -> Float {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { bound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, bound, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            //let totalMemory = ProcessInfo.processInfo.physicalMemory
            let pageSize = UInt64(getpagesize())
            let freeMemory = UInt64(stats.free_count) * pageSize
            
            // Available memory is free memory plus inactive memory that can be freed
            let inactiveMemory = UInt64(stats.inactive_count) * pageSize
            let availableMemory = Float(freeMemory + inactiveMemory)
            //let totalMemoryGB = Float(totalMemory) / (1024 * 1024 * 1024)
            let availableMemoryGB = availableMemory / (1024 * 1024 * 1024)
            
            // print("[Vision] Total Memory: \(String(format: "%.2f", totalMemoryGB))GB")
            // print("[Vision] Available Memory: \(String(format: "%.2f", availableMemoryGB))GB")
            
            return availableMemoryGB
        }
        
        // Fallback: return total physical memory if host_statistics64 fails
        //        let totalMemory = Float(ProcessInfo.processInfo.physicalMemory)
        //        let totalMemoryGB = totalMemory / (1024 * 1024 * 1024)
        //        // print("[Vision] Fallback - Total Memory: \(String(format: "%.2f", totalMemoryGB))GB")
        //        return totalMemoryGB
        return 0 //fallback
    }
    
    nonisolated private func determineBatchSize() -> Int {
        let availableMemoryGB = getAvailableMemoryInGB()
        
        switch availableMemoryGB {
        case ..<2:
            return 1  // Less than 2GB
        case 2..<3:
            return 50 // Between 2GB and 3GB
        default:
            return 100 // Greater than 3GB
        }
    }
    
    @available(iOS 18.0, *)
    public func scoreWithVision(imageIdentifiers: [String]) async -> [String] {
        // Check if already processing using actor
        let canStart = await processingState.startProcessing()
        if !canStart {
            // print("[Vision] Already processing, returning original order")
            return imageIdentifiers
        }
        
        defer {
            Task {
                await processingState.finishProcessing()
            }
        }
        
        let batchSize = determineBatchSize() // Dynamically determine batch size based on available memory
        
        //let startTime = Date()
        
        // Track scores for each identifier
        var photoScores = [(identifier: String, score: Double)]()
        
        // Get identifiers that need scoring
        let identifiersToScore = imageIdentifiers
        
        if identifiersToScore.count > 0 {
            // print("[Vision] Need to score \(identifiersToScore.count) new photos")
            
            let totalPhotos = identifiersToScore.count
            let numberOfBatches = (totalPhotos + batchSize - 1) / batchSize
            
            for batchIndex in 0..<numberOfBatches {
                let start = batchIndex * batchSize
                let end = min(start + batchSize, totalPhotos)
                let batchRange = start..<end
                let batchIdentifiers = Array(batchRange).map { identifiersToScore[$0] }
                
                //let batchStartTime = Date()
                // print("[Vision] 🔷 BATCH \(batchIndex + 1)/\(numberOfBatches) STARTED - Processing \(batchIdentifiers.count) photos")
                
                // Process the current batch - await ensures this completes before next batch starts
                let batchScores = await processBatchWithIdentifiers(identifiers: batchIdentifiers)
                
                photoScores.append(contentsOf: batchScores)
                
                //let batchTime = Date().timeIntervalSince(batchStartTime)
                // print("[Vision] ✅ BATCH \(batchIndex + 1)/\(numberOfBatches) COMPLETED in \(String(format: "%.2f", batchTime))s - Scored \(batchScores.count) photos")
            }
        }
        
        // All batches completed
        //let processingTime = Date().timeIntervalSince(startTime)
        
        // Sort by score from high to low
        photoScores.sort { $0.score > $1.score }
        
        // print("[Vision] Processing completed in \(String(format: "%.2f", processingTime)) seconds for \(imageIdentifiers.count) photos (\(identifiersToScore.count) newly scored)")
        
        // Return sorted identifiers
        return photoScores.map { $0.identifier }
    }
    
    /// Batch score all assets with location to pre-warm the cache
    /// This method should be called once after loading all albums
    /// - Parameter assets: All assets from all collections
    /// - Returns: Number of newly scored photos
    @available(iOS 18.0, *)
    public func batchScoreAssetsWithLocation(_ assets: [PHAsset]) async -> Int {
        // Check if already processing
        let canStart = await processingState.startProcessing()
        if !canStart {
            // print("[Vision] Already processing, skipping batch scoring")
            return 0
        }
        
        defer {
            Task {
                await processingState.finishProcessing()
            }
        }
        
        //let startTime = Date()
        
        // Filter assets with location
        let assetsWithLocation = assets //.filter { $0.location != nil }
        // print("[Vision] Batch scoring \(assetsWithLocation.count) photos with location out of \(assets.count) total")
        
        guard assetsWithLocation.count > 0 else {
            // print("[Vision] No assets with location to score")
            return 0
        }
        
        // Get identifiers
        let identifiers = assetsWithLocation.map { $0.localIdentifier }

        let identifiersToScore = identifiers
        
        guard identifiersToScore.count > 0 else {
            // print("[Vision] All photos already cached")
            return 0
        }
        
        // Determine batch size
        let batchSize = determineBatchSize()
        let numberOfBatches = (identifiersToScore.count + batchSize - 1) / batchSize
        
        // Process in batches
        for batchIndex in 0..<numberOfBatches {
            let start = batchIndex * batchSize
            let end = min(start + batchSize, identifiersToScore.count)
            let batchIdentifiers = Array(identifiersToScore[start..<end])
            
            //let batchStartTime = Date()
            // print("[Vision] 🔷 BATCH \(batchIndex + 1)/\(numberOfBatches) STARTED - Processing \(batchIdentifiers.count) photos")
            
            // Process the current batch - await ensures this completes before next batch starts
            let batchScores = await processBatchWithIdentifiers(identifiers: batchIdentifiers)
            
            //let batchTime = Date().timeIntervalSince(batchStartTime)
            // print("[Vision] ✅ BATCH \(batchIndex + 1)/\(numberOfBatches) COMPLETED in \(String(format: "%.2f", batchTime))s - Scored \(batchScores.count) photos")
        }
        
        //let processingTime = Date().timeIntervalSince(startTime)
        // print("[Vision] Batch scoring completed in \(String(format: "%.2f", processingTime)) seconds, scored \(identifiersToScore.count) new photos")
        
        return identifiersToScore.count
    }
    
    @available(iOS 18.0, *)
    private func processBatchWithIdentifiers(identifiers: [String]) async -> [(identifier: String, score: Double)] {
        // print("[Vision]   📸 Starting CONCURRENT processing of \(identifiers.count) images in this batch...")
        
        // Create thread-safe container for batch results using NSLock
        // Much faster than nested actor which would cause double actor isolation
        final class BatchResults: @unchecked Sendable {
            private let lock = NSLock()
            private var _photoScores: [(identifier: String, score: Double)] = []
            private var _processedCount: Int = 0
            
            func addPhotoScore(identifier: String, score: Double) {
                lock.lock()
                defer { lock.unlock() }
                _photoScores.append((identifier: identifier, score: score))
                _processedCount += 1
            }
            
            func incrementProcessed() {
                lock.lock()
                defer { lock.unlock() }
                _processedCount += 1
            }
            
            func getProcessedCount() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return _processedCount
            }
            
            func getResults() -> [(identifier: String, score: Double)] {
                lock.lock()
                defer { lock.unlock() }
                return _photoScores
            }
        }
        
        let batchResults = BatchResults()
        //let totalCount = identifiers.count
        
        // Process images CONCURRENTLY within the batch to speed up processing
        // Memory is controlled by batch size - max N images in memory at once
        await withTaskGroup(of: Void.self) { group in
            for (_, identifier) in identifiers.enumerated() {
                group.addTask {
                    //let imageStartTime = Date()
                    
                    // print("[Vision]     ⏳ Image \(index + 1)/\(totalCount): Loading...")
                    
                    // Load image from asset identifier
                    if let image = await self.loadImage(from: identifier) {
                        do {
                            // print("[Vision]     🧠 Image \(index + 1)/\(totalCount): Analyzing with Vision API...")
                            if let observation = try await ERVisionHelper.shared.calculateAestheticsScore(image: image) {
                                // Convert score from -1...1 to 1...10 to match NIMA scale
                                let normalizedScore = ((observation.overallScore + 1) / 2) * 9 + 1
                                batchResults.addPhotoScore(identifier: identifier, score: Double(normalizedScore))
                                
                                //let imageTime = Date().timeIntervalSince(imageStartTime)
                                // print("[Vision]     ✅ Image \(index + 1)/\(totalCount): Scored \(String(format: "%.2f", normalizedScore)) (took \(String(format: "%.2f", imageTime))s)")
                            } else {
                                batchResults.incrementProcessed()
                            }
                        } catch {
                            // print("[Vision]     ❌ Image \(index + 1)/\(totalCount): Analysis failed - \(error)")
                            batchResults.incrementProcessed()
                        }
                    } else {
                        // print("[Vision]     ❌ Image \(index + 1)/\(totalCount): Failed to load")
                        batchResults.incrementProcessed()
                    }
                    
                    // Log progress every 10 photos
                    let processed = batchResults.getProcessedCount()
                    if processed % 10 == 0 {
                        // print("[Vision]   📊 Progress: \(processed)/\(totalCount) photos processed in current batch")
                    }
                }
            }
        }
        
        let results = batchResults.getResults()
        // print("[Vision]   ✅ Concurrent processing complete: \(results.count)/\(identifiers.count) photos successfully scored")
        return results
    }
    
    @available(iOS 18.0, *)
    private func loadImage(from identifier: String) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else {
            return nil
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        options.isSynchronous = false
        
        let targetSize = CGSize(width: 256, height: 256)
        
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
