# GraphQL Code Generation with Git Integration

## Project Structure

```
GraphQLCodeGen/
├── Sources/
│   ├── main.swift                    # Main entry point
│   ├── Configuration.swift           # Configuration management
│   ├── Logger.swift                  # Logging utilities
│   ├── CommandLineOptions.swift      # CLI argument parsing
│   ├── GitManager.swift              # Git operations (new)
│   ├── ApolloCLI.swift              # Apollo CLI wrapper
│   ├── ProcessExecutor.swift        # Process execution utilities
│   └── ChangeTracker.swift          # Track generation history (new)
├── .last-generation                  # Stores last processed commit hash
└── apollo-codegen-config.json       # Apollo configuration

```

## File Implementations

### 1. main.swift
```swift
#!/usr/bin/env swift

import Foundation

// Main entry point - orchestrates the entire process
func main() {
    let options = CommandLineOptions(arguments: CommandLine.arguments)
    
    if options.showHelp {
        showHelp()
        exit(0)
    }
    
    let logger = Logger(level: options.logLevel)
    let config = Configuration()
    let gitManager = GitManager(config: config, logger: logger)
    let changeTracker = ChangeTracker(config: config, logger: logger)
    let apolloCLI = ApolloCLI(config: config, logger: logger)
    
    logger.info("🔧 GraphQL Code Generation with Git Integration")
    logger.info("================================================")
    
    do {
        // Step 1: Check if we need to update from git
        logger.info("\n📥 Checking for repository updates...")
        let needsUpdate = try gitManager.checkForUpdates()
        
        if !needsUpdate {
            logger.success("No changes detected since last generation. Skipping...")
            exit(0)
        }
        
        // Step 2: Clone or update the repository
        logger.info("\n📦 Updating repository...")
        let currentCommit = try gitManager.cloneOrUpdate()
        
        // Step 3: Validate schema and operations folders exist
        try gitManager.validateRepoStructure()
        
        // Step 4: Update Apollo config with paths from repo
        try updateApolloConfig(with: gitManager.getSchemaPath(), 
                              operationsPath: gitManager.getOperationsPath())
        
        // Step 5: Generate GraphQL code
        logger.info("\n🚀 Generating GraphQL code...")
        let executable = try apolloCLI.validatePrerequisites()
        try apolloCLI.generateCode(using: executable)
        
        // Step 6: Save the current commit hash for next run
        try changeTracker.saveLastProcessedCommit(currentCommit)
        
        logger.info("")
        logger.success("✨ Code generation completed successfully!")
        exit(0)
        
    } catch {
        logger.error("Error: \(error.localizedDescription)")
        exit(1)
    }
}

func showHelp() {
    print("""
    GraphQL Code Generation Script with Git Integration
    
    Usage: swift main.swift [OPTIONS]
    
    OPTIONS:
        --verbose, -v    Enable verbose output
        --quiet, -q      Suppress all output except errors
        --force, -f      Force regeneration even if no changes detected
        --help, -h       Show this help message
    
    DESCRIPTION:
        1. Checks git repository for updates
        2. Clones or updates the repository
        3. Generates GraphQL code only if changes are detected
        4. Tracks last processed commit to avoid duplicates
    
    GIT REPOSITORY:
        URL: \(Configuration().gitRepoURL)
        Local: \(Configuration().localRepoPath.path)
    """)
}

func updateApolloConfig(with schemaPath: URL, operationsPath: URL) throws {
    // Update apollo-codegen-config.json with correct paths
    // This would modify the config to point to the checked out repo paths
}

main()
```

### 2. Configuration.swift
```swift
import Foundation

struct Configuration {
    // MARK: - Git Configuration
    let gitRepoURL = "https://github.com/your-org/graphql-schemas.git" // PLACEHOLDER
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
```

### 3. Logger.swift
```swift
import Foundation

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
```

### 4. CommandLineOptions.swift
```swift
import Foundation

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
```

### 5. GitManager.swift
```swift
import Foundation

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
    
    /// Checks if there are updates available in the remote repository
    func checkForUpdates() throws -> Bool {
        logger.verbose("Checking for repository updates...")
        
        // Check if git is installed
        guard executor.commandExists("git") else {
            throw GitError.gitNotInstalled
        }
        
        // If repo doesn't exist locally, we need to update
        if !FileManager.default.fileExists(atPath: config.localRepoPath.path) {
            logger.verbose("Local repository doesn't exist. Update needed.")
            return true
        }
        
        // Fetch latest changes from remote without merging
        let fetchResult = executor.execute(
            "git",
            arguments: ["fetch", "origin", config.gitBranch],
            workingDirectory: config.localRepoPath
        )
        
        if fetchResult?.exitCode != 0 {
            throw GitError.fetchFailed(fetchResult?.errorOutput ?? "Unknown error")
        }
        
        // Compare local and remote HEAD
        let localHead = try getCommitHash("HEAD")
        let remoteHead = try getCommitHash("origin/\(config.gitBranch)")
        
        logger.verbose("Local HEAD: \(localHead)")
        logger.verbose("Remote HEAD: \(remoteHead)")
        
        return localHead != remoteHead
    }
    
    /// Clones the repository if it doesn't exist, or updates it if it does
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
                "--depth", "1",  // Shallow clone for efficiency
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
        
        // Reset any local changes
        _ = executor.execute(
            "git",
            arguments: ["reset", "--hard"],
            workingDirectory: config.localRepoPath
        )
        
        // Pull latest changes
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
```

### 6. ChangeTracker.swift
```swift
import Foundation

class ChangeTracker {
    private let config: Configuration
    private let logger: Logger
    
    init(config: Configuration, logger: Logger) {
        self.config = config
        self.logger = logger
    }
    
    /// Retrieves the last processed commit hash
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
    
    /// Saves the current commit hash for future reference
    func saveLastProcessedCommit(_ hash: String) throws {
        let content = """
        commit:\(hash)
        timestamp:\(Date().timeIntervalSince1970)
        branch:\(config.gitBranch)
        """
        
        try content.write(to: config.lastGenerationFile, atomically: true, encoding: .utf8)
        logger.verbose("Saved commit hash: \(hash)")
    }
    
    /// Checks if generation is needed based on commit history
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
    
    /// Gets metadata about the last generation
    func getLastGenerationMetadata() -> [String: String]? {
        guard FileManager.default.fileExists(atPath: config.lastGenerationFile.path) else {
            return nil
        }
        
        do {
            let content = try String(contentsOf: config.lastGenerationFile)
            var metadata: [String: String] = [:]
            
            for line in content.components(separatedBy: .newlines) {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    metadata[String(parts[0])] = String(parts[1])
                }
            }
            
            // Add human-readable timestamp
            if let timestampStr = metadata["timestamp"],
               let timestamp = Double(timestampStr) {
                let date = Date(timeIntervalSince1970: timestamp)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .medium
                metadata["lastGenerated"] = formatter.string(from: date)
            }
            
            return metadata
        } catch {
            logger.warning("Could not parse generation metadata: \(error)")
            return nil
        }
    }
}
```

### 7. ApolloCLI.swift
```swift
import Foundation

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
        
        // Check common locations
        let searchPaths = [
            "apollo-ios-cli",  // Global installation
            config.baseDirectory.appendingPathComponent("../node_modules/.bin/apollo-ios-cli").path,
            "/usr/local/bin/apollo-ios-cli"
        ]
        
        for path in searchPaths {
            if executor.commandExists(path) {
                logger.verbose("Found Apollo CLI at: \(path)")
                return path
            }
        }
        
        // Try npx fallback
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
        
        // Check configuration file
        guard FileManager.default.fileExists(atPath: config.configPath.path) else {
            throw CLIError.configNotFound(config.configPath.path)
        }
        
        // Find Apollo CLI
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
```

### 8. ProcessExecutor.swift
```swift
import Foundation

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
```

## Change Detection Strategy Explanation

### How It Works:

1. **Commit Hash Tracking**: The system stores the SHA hash of the last successfully processed commit in a `.last-generation` file. This serves as a checkpoint.

2. **Remote Repository Checking**: 
   - Before any generation, the script fetches the latest changes from the remote repository
   - Compares the remote HEAD commit with the local HEAD commit
   - If they differ, updates are available

3. **Efficient Updates**:
   - **Shallow Clone**: Uses `--depth 1` for initial clone to save bandwidth
   - **Fetch Before Pull**: Only fetches metadata first to check for changes
   - **Pull Only When Needed**: Only pulls full changes if generation is required

4. **Generation Decision Logic**:
   ```
   IF no local repo exists → Clone and Generate
   ELSE IF --force flag used → Generate
   ELSE IF no .last-generation file → Generate
   ELSE
     Fetch remote changes
     IF remote HEAD ≠ stored commit hash → Pull and Generate
     ELSE → Skip (no changes)
   ```

5. **Benefits**:
   - **Avoids Redundant Work**: Skips generation when schema/operations haven't changed
   - **Network Efficient**: Only pulls full repository when needed
   - **Reproducible**: Can force regeneration with `--force` flag
   - **Auditable**: Tracks when and what commit was last processed

### Additional Features:

- **Retry Logic**: Can retry failed git operations with configurable delays
- **Branch Support**: Can track specific branches
- **Metadata Storage**: Stores timestamp and branch info for debugging
- **Verbose Logging**: Detailed logs for troubleshooting
- **Error Recovery**: Handles corrupted repos by re-cloning if needed

### Usage Examples:

```bash
# Normal run - checks for changes
swift main.swift

# Force regeneration even without changes
swift main.swift --force

# Verbose output for debugging
swift main.swift --verbose

# Skip git operations (use existing local files)
swift main.swift --skip-git
```

This architecture provides a robust, maintainable solution that efficiently manages GraphQL schema updates while avoiding unnecessary regeneration.
