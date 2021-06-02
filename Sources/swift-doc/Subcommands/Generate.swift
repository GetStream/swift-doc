import ArgumentParser
import Foundation
import SwiftDoc
import SwiftMarkup
import SwiftSemantics
import struct SwiftSemantics.Protocol

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension SwiftDoc {
  struct Generate: ParsableCommand {
    enum Format: String, ExpressibleByArgument {
      case commonmark
      case html
    }

    struct Options: ParsableArguments {
      @Argument(help: "One or more paths to a directory containing Swift files.")
      var inputs: [String]

      @Option(name: [.long, .customShort("n")],
              help: "The name of the module")
      var moduleName: String

      @Option(name: .shortAndLong,
              help: "The path for generated output")
      var output: String = ".build/documentation"

      @Option(name: .shortAndLong,
              help: "The output format")
      var format: Format = .commonmark

      @Option(name: .customLong("base-url"),
              help: "The base URL used for all relative URLs in generated documents.")
      var baseURL: String = "/"

      @Option(name: .long,
              help: "The minimum access level of the symbols included in generated documentation.")
      var minimumAccessLevel: AccessLevel = .public
    }

    static var configuration = CommandConfiguration(abstract: "Generates Swift documentation")

    @OptionGroup()
    var options: Options

    func run() throws {
        guard options.inputs.count == 1 else {
            logger.error("Stream fork only allows 1 input directory")
            return
        }
        
      for directory in options.inputs {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) {
          logger.warning("Input path \(directory) does not exist.")
        } else if !isDirectory.boolValue {
          logger.warning("Input path \(directory) is not a directory.")
        }
      }
        
        let startDirectory = URL(fileURLWithPath: options.inputs.first!, isDirectory: true)
        //print("START DIR \(startDirectory)")
        //print("START DIR ABS \(startDirectory.absoluteString)")
      let module = try Module(name: options.moduleName, paths: options.inputs)
      let baseURL = options.baseURL

      let outputDirectoryURL = URL(fileURLWithPath: options.output)
      try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

      do {
        let format = options.format

        var pages: [String: (Page, Symbol?)] = [:]

        var globals: [String: [Symbol]] = [:]
        let symbolFilter = options.minimumAccessLevel.includes(symbol:)
        for symbol in module.interface.topLevelSymbols.filter(symbolFilter) {
          switch symbol.api {
          case is Class, is Enumeration, is Structure, is Protocol:
            pages[route(for: symbol)] = (TypePage(module: module, symbol: symbol, baseURL: baseURL, includingChildren: symbolFilter), symbol)
          case let `typealias` as Typealias:
            pages[route(for: `typealias`.name)] = (TypealiasPage(module: module, symbol: symbol, baseURL: baseURL, includingOtherSymbols: symbolFilter), symbol)
          case is Operator:
            let operatorPage = OperatorPage(module: module, symbol: symbol, baseURL: baseURL, includingImplementations: symbolFilter)
            if !operatorPage.implementations.isEmpty {
              pages[route(for: symbol)] = (operatorPage, symbol)
            }
          case let function as Function where !function.isOperator:
            globals[function.name, default: []] += [symbol]
          case let variable as Variable:
            globals[variable.name, default: []] += [symbol]
          default:
            continue
          }
        }

        // Extensions on external types.
        var symbolsByExternalType: [String: [Symbol]] = [:]
        for symbol in module.interface.symbols.filter(symbolFilter) {
          guard let extensionDeclaration = symbol.context.first as? Extension, symbol.context.count == 1 else { continue }
          guard module.interface.symbols(named: extensionDeclaration.extendedType, resolvingTypealiases: true).isEmpty else { continue }
          symbolsByExternalType[extensionDeclaration.extendedType, default: []] += [symbol]
        }
        for (typeName, symbols) in symbolsByExternalType {
            let firstSymbol = symbols.first!
            //print("EXTERNAL TYPE \(typeName), SYMBOL COUNT \(symbols.count), FIRST SYMBOL PATH \(firstSymbol.filePath)")
            pages[route(for: typeName)] = (ExternalTypePage(module: module, externalType: typeName, symbols: symbols, baseURL: baseURL, includingOtherSymbols: symbolFilter), firstSymbol)
        }

        for (name, symbols) in globals {
            let firstSymbol = symbols.first!
            //print("GLOBAL PAGE \(name), SYMBOL COUNT \(symbols.count), FIRST SYMBOL PATH \(firstSymbol.filePath)")
            pages[route(for: name)] = (GlobalPage(module: module, name: name, symbols: symbols, baseURL: baseURL, includingOtherSymbols: symbolFilter), firstSymbol)
        }

        guard !pages.isEmpty else {
            logger.warning("No public API symbols were found at the specified path. No output was written.")
            if options.minimumAccessLevel == .public {
              logger.warning("By default, swift-doc only includes public declarations. Maybe you want to use --minimum-access-level to include non-public declarations?")
            }
            return
        }

        if pages.count == 1, let page = pages.first?.value.0 {
          let filename: String
          switch format {
          case .commonmark:
            filename = "Home.md"
          case .html:
            filename = "index.html"
          }

          let url = outputDirectoryURL.appendingPathComponent(filename)
          try page.write(to: url, format: format)
        } else {
          switch format {
          case .commonmark:
            pages["Home"] = (HomePage(module: module, externalTypes: Array(symbolsByExternalType.keys), baseURL: baseURL, symbolFilter: symbolFilter), nil)
            pages["_Sidebar"] = (SidebarPage(module: module, externalTypes: Set(symbolsByExternalType.keys), baseURL: baseURL, symbolFilter: symbolFilter), nil)
            pages["_Footer"] = (FooterPage(baseURL: baseURL), nil)
          case .html:
            pages["Home"] = (HomePage(module: module, externalTypes: Array(symbolsByExternalType.keys), baseURL: baseURL, symbolFilter: symbolFilter), nil)
          }

          try pages.map { $0 }.parallelForEach {
            let filename: String
            switch format {
            case .commonmark:
              filename = "\(path(for: $0.key)).md"
            case .html where $0.key == "Home":
              filename = "index.html"
            case .html:
              filename = "\(path(for: $0.key))/index.html"
            }

            if let symbol = $0.value.1 {
                let path1 = URL(fileURLWithPath: String(symbol.filePath.dropFirst("file://".count)))
                let path2 = path1.deletingLastPathComponent().appendingPathComponent(filename)
                let path3 = String(path2.absoluteString.dropFirst(startDirectory.absoluteString.count))
                //print("SYMBOL filePath \(symbol.filePath)")
                //print("SYMBOL URL \(path1.absoluteString)")
                //print("SYMBOL RELATIVE URL \(path3)")
                try $0.value.0.write(to: outputDirectoryURL.appendingPathComponent(path3), format: format)
            } else {
                let url = outputDirectoryURL.appendingPathComponent(filename)
                try $0.value.0.write(to: url, format: format)
            }
          }
        }

        if case .html = format {
          let cssData = css.data(using: .utf8)!
          let cssURL = outputDirectoryURL.appendingPathComponent("all.css")
          try writeFile(cssData, to: cssURL)
        }

      } catch {
        logger.error("\(error)")
      }
    }
  }
}

extension Symbol {
    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
}
