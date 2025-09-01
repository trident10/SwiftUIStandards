#!/usr/bin/env swift

import Foundation

// MARK: - Configuration

struct Configuration {
    // MARK: - Git Configuration
    let gitRepoURL = "https://github.com/your-org/graphql-schemas.git" // PLACEHOLDER - UPDATE THIS!
    let gitBranch = "main"
    
    // MARK: - Paths
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
    lazy var baseDirectory = scriptURL.deletingLastPathComponent()
    
    lazy var localRepoPath = baseDirectory
        .appendingPathComponent(".graphql-repo")
        .standardized
    
    lazy var schemaFolderName = "schema"
    lazy var operationsFolderName = "operations"
    
    lazy var configPath = baseDirectory
        .appendingPathComponent("apollo-codegen-config.json")
        .standardized
    
    lazy var lastGenerationFile = baseDirectory
        .appendingPathComponent(".last-generation")
        .standardized
    
    lazy var generatedCodePath = baseDirectory
        .appendingPathComponent("..")
        .appendingPathComponent("Generated")
        .standardized
    
    // MARK: - Settings
    let checkRemoteForUpdates = true
    let autoCleanGeneratedFiles = false
    let maxRetries = 3
    let retryDelay: TimeInterval = 2.0
}

// MARK: - Logger

enum LogLevel {
    case quiet, normal, verbose
}

struct Logger {
    let level: LogLevel
    private let dateFormatter: DateFormatter
    
    init(level: LogLevel) {
        self.level = level
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss"
    }
    
    func info(_ message: String) {
        guard level != .quiet else { return }
        print(message)
    }
    
    func verbose(_ message: String) {
        guard level == .verbose else { return }
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] 🔍 \(message)")
    }
    
    func success(_ message: String) {
        guard level != .quiet else { return }
        print("✅ \(message)")
    }
    
    func error(_ message: String) {
        fputs("❌ \(message)\n", stderr)
    }
    
    func warning(_ message: String) {
        guard level != .quiet else { return }
        print("⚠️ \(message)")
    }
    
    func progress(_ message: String) {
        guard level != .quiet else { return }
        print("⏳ \(message)")
    }
}

// MARK: - Command Line Options

struct CommandLineOptions {
    var logLevel: LogLevel = .normal
    var showHelp = false
    var forceRegeneration = false
    var skipGitUpdate = false
    
    init(arguments: [String]) {
        for arg in arguments.dropFirst() {
            switch arg {
            case "--verbose", "-v":
                logLevel = .verbose
            case "--quiet", "-q":
                logLevel = .quiet
            case "--help", "-h":
                showHelp = true
            case "--force", "-f":
                forceRegeneration = true
            case "--skip-git":
                skipGitUpdate = true
            default:
                if !arg.starts(with: "-") {
                    continue
                }
                print("❌ Unknown option: \(arg)")
                showHelp = true
            }
        }
    }
}

// MARK: - Process Executor

struct ProcessResult {
    let exitCode: Int32
    let output: String
    let errorOutput: String
}

class ProcessExecutor {
    func execute(_ command: String, 
                arguments: [String] = [], 
                workingDirectory: URL? = nil) -> ProcessResult? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        if let workingDir = workingDirectory {
            process.currentDirectoryURL = workingDir
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            return ProcessResult(
                exitCode: process.terminationStatus,
                output: String(data: outputData, encoding: .utf8) ?? "",
                errorOutput: String(data: errorData, encoding: .utf8) ?? ""
            )
        } catch {
            return nil
        }
    }
    
    func commandExists(_ command: String) -> Bool {
        let result = execute("/usr/bin/which", arguments: [command])
        return result?.exitCode == 0
    }
}

// MARK: - Git Manager

class GitManager {
    enum GitError: Error, LocalizedError {
        case gitNotInstalled
        case cloneFailed(String)
        case fetchFailed(String)
        case checkoutFailed(String)
        case invalidRepository
        case missingSchemaFolder
        case missingOperationsFolder
        
        var errorDescription: String? {
            switch self {
            case .gitNotInstalled:
                return "Git is not installed or not in PATH"
            case .cloneFailed(let message):
                return "Failed to clone repository: \(message)"
            case .fetchFailed(let message):
                return "Failed to fetch updates: \(message)"
            case .checkoutFailed(let message):
                return "Failed to checkout branch: \(message)"
            case .invalidRepository:
                return "Invalid or corrupted repository"
            case .missingSchemaFolder:
                return "Schema folder not found in repository"
            case .missingOperationsFolder:
                return "Operations folder not found in repository"
            }
        }
    }
    
    private let config: Configuration
    private let logger: Logger
    private let executor = ProcessExecutor()
    
    init(config: Configuration, logger: Logger) {
        self.config = config
        self.logger = logger
    }
    
    func checkForUpdates() throws -> Bool {
        logger.verbose("Checking for repository updates...")
        
        guard executor.commandExists("git") else {
            throw GitError.gitNotInstalled
        }
        
        if !FileManager.default.fileExists(atPath: config.localRepoPath.path) {
            logger.verbose("Local repository doesn't exist. Update needed.")
            return true
        }
        
        let fetchResult = executor.execute(
            "git",
            arguments: ["fetch", "origin", config.gitBranch],
            workingDirectory: config.localRepoPath
        )
        
        if fetchResult?.exitCode != 0 {
            throw GitError.fetchFailed(fetchResult?.errorOutput ?? "Unknown error")
        }
        
        let localHead = try getCommitHash("HEAD")
        let remoteHead = try getCommitHash("origin/\(config.gitBranch)")
        
        logger.verbose("Local HEAD: \(localHead)")
        logger.verbose("Remote HEAD: \(remoteHead)")
        
        return localHead != remoteHead
    }
    
    func cloneOrUpdate() throws -> String {
        if !FileManager.default.fileExists(atPath: config.localRepoPath.path) {
            try cloneRepository()
        } else {
            try updateRepository()
        }
        
        return try getCommitHash("HEAD")
    }
    
    private func cloneRepository() throws {
        logger.info("Cloning repository from \(config.gitRepoURL)...")
        
        let result = executor.execute(
            "git",
            arguments: [
                "clone",
                "--branch", config.gitBranch,
                "--single-branch",
                "--depth", "1",
                config.gitRepoURL,
                config.localRepoPath.path
            ]
        )
        
        if result?.exitCode != 0 {
            throw GitError.cloneFailed(result?.errorOutput ?? "Unknown error")
        }
        
        logger.success("Repository cloned successfully")
    }
    
    private func updateRepository() throws {
        logger.info("Updating existing repository...")
        
        _ = executor.execute(
            "git",
            arguments: ["reset", "--hard"],
            workingDirectory: config.localRepoPath
        )
        
        let result = executor.execute(
            "git",
            arguments: ["pull", "origin", config.gitBranch],
            workingDirectory: config.localRepoPath
        )
        
        if result?.exitCode != 0 {
            throw GitError.fetchFailed(result?.errorOutput ?? "Unknown error")
        }
        
        logger.success("Repository updated successfully")
    }
    
    private func getCommitHash(_ ref: String) throws -> String {
        let result = executor.execute(
            "git",
            arguments: ["rev-parse", ref],
            workingDirectory: config.localRepoPath
        )
        
        guard let output = result?.output.trimmingCharacters(in: .whitespacesAndNewlines),
              result?.exitCode == 0 else {
            throw GitError.invalidRepository
        }
        
        return output
    }
    
    func validateRepoStructure() throws {
        let schemaPath = getSchemaPath()
        let operationsPath = getOperationsPath()
        
        if !FileManager.default.fileExists(atPath: schemaPath.path) {
            throw GitError.missingSchemaFolder
        }
        
        if !FileManager.default.fileExists(atPath: operationsPath.path) {
            throw GitError.missingOperationsFolder
        }
        
        logger.verbose("Repository structure validated")
    }
    
    func getSchemaPath() -> URL {
        return config.localRepoPath
            .appendingPathComponent(config.schemaFolderName)
    }
    
    func getOperationsPath() -> URL {
        return config.localRepoPath
            .appendingPathComponent(config.operationsFolderName)
    }
}

// MARK: - Change Tracker

class ChangeTracker {
    private let config: Configuration
    private let logger: Logger
    
    init(config: Configuration, logger: Logger) {
        self.config = config
        self.logger = logger
    }
    
    func getLastProcessedCommit() -> String? {
        guard FileManager.default.fileExists(atPath: config.lastGenerationFile.path) else {
            logger.verbose("No previous generation record found")
            return nil
        }
        
        do {
            let content = try String(contentsOf: config.lastGenerationFile)
            let lines = content.components(separatedBy: .newlines)
            
            if let commitLine = lines.first(where: { $0.starts(with: "commit:") }) {
                let hash = commitLine.replacingOccurrences(of: "commit:", with: "").trimmingCharacters(in: .whitespaces)
                logger.verbose("Last processed commit: \(hash)")
                return hash
            }
        } catch {
            logger.warning("Could not read last generation file: \(error)")
        }
        
        return nil
    }
    
    func saveLastProcessedCommit(_ hash: String) throws {
        let content = """
        commit:\(hash)
        timestamp:\(Date().timeIntervalSince1970)
        branch:\(config.gitBranch)
        """
        
        try content.write(to: config.lastGenerationFile, atomically: true, encoding: .utf8)
        logger.verbose("Saved commit hash: \(hash)")
    }
    
    func needsGeneration(currentCommit: String, forceRegeneration: Bool = false) -> Bool {
        if forceRegeneration {
            logger.info("Force regeneration requested")
            return true
        }
        
        guard let lastCommit = getLastProcessedCommit() else {
            logger.info("No previous generation found. Generation needed.")
            return true
        }
        
        if lastCommit == currentCommit {
            logger.info("Current commit matches last processed. No generation needed.")
            return false
        }
        
        logger.info("New commit detected. Generation needed.")
        return true
    }
}

// MARK: - Apollo CLI

class ApolloCLI {
    enum CLIError: Error, LocalizedError {
        case notFound
        case executionFailed(Int32)
        case configNotFound(String)
        
        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Apollo iOS CLI not found. Please install: npm install -g @apollo/ios-cli"
            case .executionFailed(let code):
                return "Apollo CLI execution failed with exit code: \(code)"
            case .configNotFound(let path):
                return "Configuration file not found: \(path)"
            }
        }
    }
    
    private let config: Configuration
    private let logger: Logger
    private let executor = ProcessExecutor()
    
    init(config: Configuration, logger: Logger) {
        self.config = config
        self.logger = logger
    }
    
    func findExecutable() -> String? {
        logger.verbose("Searching for Apollo iOS CLI...")
        
        let searchPaths = [
            "apollo-ios-cli",
            config.baseDirectory.appendingPathComponent("../node_modules/.bin/apollo-ios-cli").path,
            "/usr/local/bin/apollo-ios-cli"
        ]
        
        for path in searchPaths {
            if executor.commandExists(path) {
                logger.verbose("Found Apollo CLI at: \(path)")
                return path
            }
        }
        
        if executor.commandExists("npx") {
            let result = executor.execute("npx", arguments: ["--quiet", "apollo-ios-cli", "--version"])
            if result?.exitCode == 0 {
                logger.verbose("Found apollo-ios-cli via npx")
                return "npx apollo-ios-cli"
            }
        }
        
        return nil
    }
    
    func validatePrerequisites() throws -> String {
        logger.verbose("Validating Apollo CLI prerequisites...")
        
        guard FileManager.default.fileExists(atPath: config.configPath.path) else {
            throw CLIError.configNotFound(config.configPath.path)
        }
        
        guard let executable = findExecutable() else {
            throw CLIError.notFound
        }
        
        return executable
    }
    
    func generateCode(using executable: String) throws {
        logger.progress("Running Apollo code generation...")
        
        var arguments = ["generate", "--path", config.configPath.path]
        
        if logger.level == .verbose {
            arguments.append("--verbose")
        }
        
        let components = executable.components(separatedBy: " ")
        let command = components.first!
        let commandArgs = Array(components.dropFirst()) + arguments
        
        guard let result = executor.execute(command, arguments: commandArgs) else {
            throw CLIError.executionFailed(-1)
        }
        
        if result.exitCode == 0 {
            logger.success("GraphQL code generated successfully!")
        } else {
            logger.error("Generation failed: \(result.errorOutput)")
            throw CLIError.executionFailed(result.exitCode)
        }
    }
}

// MARK: - Main Functions

func showHelp(config: Configuration) {
    print("""
    GraphQL Code Generation Script with Git Integration
    
    Usage: swift GraphQLGen.swift [OPTIONS]
           ./GraphQLGen.swift [OPTIONS]  (if executable)
    
    OPTIONS:
        --verbose, -v    Enable verbose output
        --quiet, -q      Suppress all output except errors
        --force, -f      Force regeneration even if no changes detected
        --skip-git       Skip git operations (use existing local files)
        --help, -h       Show this help message
    
    DESCRIPTION:
        1. Checks git repository for updates
        2. Clones or updates the repository
        3. Generates GraphQL code only if changes are detected
        4. Tracks last processed commit to avoid duplicates
    
    GIT REPOSITORY:
        URL: \(config.gitRepoURL)
        Branch: \(config.gitBranch)
        Local: \(config.localRepoPath.path)
    
    EXAMPLES:
        swift GraphQLGen.swift
        swift GraphQLGen.swift --verbose
        swift GraphQLGen.swift --force
        ./GraphQLGen.swift --quiet
    """)
}

func updateApolloConfig(config: Configuration, schemaPath: URL, operationsPath: URL) throws {
    // This function would update the apollo-codegen-config.json
    // with the correct paths from the checked out repository
    // For now, this is a placeholder implementation
    
    // In a real implementation, you would:
    // 1. Read the existing apollo-codegen-config.json
    // 2. Update the schema and operations paths
    // 3. Write it back
    
    // Example structure of apollo-codegen-config.json:
    let configContent = """
    {
      "schemaSearchPaths": [
        "\(schemaPath.path)/**/*.graphqls"
      ],
      "operationSearchPaths": [
        "\(operationsPath.path)/**/*.graphql"
      ],
      "outputPath": "./Generated"
    }
    """
    
    // For now, just validate that config exists
    if !FileManager.default.fileExists(atPath: config.configPath.path) {
        // Create a default config if it doesn't exist
        try configContent.write(to: config.configPath, atomically: true, encoding: .utf8)
    }
}

func main() {
    let options = CommandLineOptions(arguments: CommandLine.arguments)
    let config = Configuration()
    
    if options.showHelp {
        showHelp(config: config)
        exit(0)
    }
    
    let logger = Logger(level: options.logLevel)
    let gitManager = GitManager(config: config, logger: logger)
    let changeTracker = ChangeTracker(config: config, logger: logger)
    let apolloCLI = ApolloCLI(config: config, logger: logger)
    
    logger.info("🔧 GraphQL Code Generation with Git Integration")
    logger.info("================================================")
    
    do {
        var currentCommit: String = ""
        
        if !options.skipGitUpdate {
            // Step 1: Check if we need to update from git
            logger.info("\n📥 Checking for repository updates...")
            
            if !options.forceRegeneration {
                let lastCommit = changeTracker.getLastProcessedCommit()
                if lastCommit != nil {
                    let needsUpdate = try gitManager.checkForUpdates()
                    if !needsUpdate {
                        logger.success("No changes detected since last generation. Skipping...")
                        logger.info("Use --force to regenerate anyway")
                        exit(0)
                    }
                }
            }
            
            // Step 2: Clone or update the repository
            logger.info("\n📦 Updating repository...")
            currentCommit = try gitManager.cloneOrUpdate()
            
            // Step 3: Validate schema and operations folders exist
            try gitManager.validateRepoStructure()
            
            // Step 4: Update Apollo config with paths from repo
            try updateApolloConfig(
                config: config,
                schemaPath: gitManager.getSchemaPath(),
                operationsPath: gitManager.getOperationsPath()
            )
        } else {
            logger.info("Skipping git operations (--skip-git flag)")
        }
        
        // Step 5: Generate GraphQL code
        logger.info("\n🚀 Generating GraphQL code...")
        let executable = try apolloCLI.validatePrerequisites()
        try apolloCLI.generateCode(using: executable)
        
        // Step 6: Save the current commit hash for next run
        if !options.skipGitUpdate && !currentCommit.isEmpty {
            try changeTracker.saveLastProcessedCommit(currentCommit)
        }
        
        logger.info("")
        logger.success("✨ Code generation completed successfully!")
        exit(0)
        
    } catch {
        logger.error("Error: \(error.localizedDescription)")
        exit(1)
    }
}

// Execute main function
main()
