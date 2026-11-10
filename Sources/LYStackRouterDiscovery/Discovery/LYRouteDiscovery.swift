#if canImport(UIKit)
    import MachO

    /// 写入 `__DATA,__lystackrouter` 的一条发现记录：格式标识与登记函数。
    ///
    /// 登记函数是不捕获任何值的 C 函数指针，由 `@LYRouteModule` 宏在编译期生成，
    /// 运行时读取方传入收集上下文调用它。
    public typealias LYRouteDiscoveryRecord = (UInt64, @convention(c) (UnsafeMutableRawPointer) -> Void)

    /// 读取已加载镜像中的发现记录，得到所有标注了 `@LYRouteModule` 的模块类型。
    ///
    /// 只在构建路由器时由 `LYRouteModuleSet.discovered` 调用，不依赖 ObjC `+load`，也不扫描类表。
    public enum LYRouteDiscovery {
        // MARK: - Properties

        /// 与宏生成的记录一致的格式标识（"LYSR" + 版本 1）。
        static let recordMagic: UInt64 = 0x4C59_5352_0000_0001

        static let segmentName = "__DATA"
        static let sectionName = "__lystackrouter"

        // MARK: - Public

        /// 仅供 `@LYRouteModule` 宏展开调用：把模块类型交给收集上下文。
        ///
        /// 泛型约束让编译器检查被标注的类型确实遵循 `LYRouteModule`；这里只传递元类型，不创建模块。
        public static func collect(_ context: UnsafeMutableRawPointer, _ module: (some LYRouteModule).Type) {
            context.assumingMemoryBound(to: [Any.Type].self).pointee.append(module)
        }

        // MARK: - Internal

        /// 遍历当前已加载的全部镜像，按记录在 section 中的顺序返回模块类型。
        ///
        /// 格式标识不符或 section 大小不是记录大小整数倍的镜像会被跳过，避免误读其他数据。
        static func moduleTypes() -> [Any.Type] {
            var found: [Any.Type] = []
            withUnsafeMutablePointer(to: &found) { pointer in
                let context = UnsafeMutableRawPointer(pointer)
                for index in 0 ..< _dyld_image_count() {
                    guard let header = _dyld_get_image_header(index) else { continue }
                    var size: UInt = 0
                    let section = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
                        getsectiondata($0, segmentName, sectionName, &size)
                    }
                    let stride = MemoryLayout<LYRouteDiscoveryRecord>.stride
                    guard let section, size > 0, Int(size) % stride == 0 else { continue }
                    let count = Int(size) / stride
                    section.withMemoryRebound(to: LYRouteDiscoveryRecord.self, capacity: count) { start in
                        for record in UnsafeBufferPointer(start: start, count: count) where record.0 == recordMagic {
                            record.1(context)
                        }
                    }
                }
            }
            return found
        }
    }
#endif
