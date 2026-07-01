# [icp-runtime-bridge](https://central.ballerina.io/wso2/icp.runtime.bridge/)

[![Daily build](https://github.com/wso2/icp-runtime-bridge/actions/workflows/daily-build.yml/badge.svg)](https://github.com/wso2/icp-runtime-bridge/actions/workflows/daily-build.yml)

## Overview

The `icp-runtime-bridge` is a Ballerina library that provides a runtime bridge between Ballerina Integrator(BI) runtime and the WSO2 Integration Control Plane (ICP). It enables centralized monitoring, management, and control of distributed integration runtimes through secure communication channels.

### Key Features

- **Secure Runtime Registration**: Automatic registration of integration runtimes with ICP using JWT-based authentication
- **Heartbeat Monitoring**: Periodic health status reporting to maintain runtime visibility
- **Artifact Synchronization**: Real-time synchronization of deployed artifacts, services, and APIs
- **Status Monitoring**: Continuous tracking of runtime and artifact states (RUNNING, OFFLINE, etc.)
- **Configuration Management**: Flexible configuration through environment variables or TOML files
- **Native Performance**: Built with Java 21 platform dependencies for optimal performance

## Architecture

The bridge operates as an agent within Ballerina runtime environments and consists of several key components:

- **ICP Client**: Handles secure HTTP communication with the ICP server
- **Heartbeat Service**: Sends periodic status updates to maintain runtime visibility
- **Artifact Manager**: Monitors and reports deployed artifacts (services, APIs, listeners)
- **Configuration Manager**: Manages runtime configuration and credentials
- **Security Module**: Handles JWT generation and secure authentication

## Building the Project

### Prerequisites

- **Java 21** (Temurin distribution recommended)
- **Ballerina** 2201.13.2
- **Gradle** (included via wrapper)

### Build Commands

```bash
# Build the entire project
./gradlew clean build

# Build only the native Java components
./gradlew :native:build

# Build only the Ballerina package
./gradlew :ballerina:build

# Run tests
./gradlew test
```

### Build Outputs

- Ballerina package: `ballerina/build/distributions/*.zip`
- Native JAR: `native/build/libs/icp.runtime.bridge-native-*.jar`
- Test reports: `ballerina-tests/build/reports/`

## Configuration

The runtime bridge can be configured using environment variables or a `Config.toml` file.

### Environment Variables

Ballerina configurable variables can be set via environment variables using the `BAL_CONFIG_VAR_` prefix:

```bash
# ICP Server Configuration (Required)
BAL_CONFIG_VAR_SERVER_URL=https://icp.example.com
BAL_CONFIG_VAR_SECRET=your-shared-secret-key

# Connection Settings
BAL_CONFIG_VAR_HEARTBEAT_INTERVAL=10
BAL_CONFIG_VAR_ENABLE_SSL=true
BAL_CONFIG_VAR_CERT=/path/to/certificate.pem

# JWT Configuration
BAL_CONFIG_VAR_JWT_ISSUER=icp-runtime-jwt-issuer
BAL_CONFIG_VAR_JWT_AUDIENCE=icp-server
BAL_CONFIG_VAR_JWT_EXPIRY_TIME_SECONDS=3600

# Runtime Identity
BAL_CONFIG_VAR_RUNTIME=runtime-001
BAL_CONFIG_VAR_ENVIRONMENT=Production
BAL_CONFIG_VAR_INTEGRATION=my-integration
BAL_CONFIG_VAR_PROJECT=my-project
```

### Config.toml Example

```toml
# ICP Server Configuration (Required)
serverUrl = "https://icp.example.com"
secret = "your-shared-secret-key"

# Connection Settings
heartbeatInterval = 10
enableSSL = true
cert = "/path/to/certificate.pem"

# JWT Configuration
jwtIssuer = "icp-runtime-jwt-issuer"
jwtAudience = "icp-server"
jwtExpiryTimeSeconds = 3600.0

# Runtime Identity
runtime = "runtime-001"
environment = "Production"
integration = "my-integration"
project = "my-project"
```

### Configuration Parameters

| Parameter              | Type            | Default                  | Required | Description                        |
| ---------------------- | --------------- | ------------------------ | -------- | ---------------------------------- |
| `serverUrl`            | string          | "https://localhost:9445" | Yes      | ICP server base URL                |
| `secret`               | string          | -                        | Yes      | Shared secret for JWT generation   |
| `heartbeatInterval`    | int             | 10                       | No       | Heartbeat interval in seconds      |
| `enableSSL`            | boolean         | false                    | No       | Enable SSL/TLS for connections     |
| `cert`                 | string          | ""                       | No       | Path to certificate file           |
| `jwtIssuer`            | string          | "icp-runtime-jwt-issuer" | No       | JWT issuer identifier              |
| `jwtAudience`          | string/string[] | "icp-server"             | No       | JWT audience claim                 |
| `jwtExpiryTimeSeconds` | decimal         | 3600                     | No       | JWT expiration time in seconds     |
| `runtime`              | string          | Generated UUID           | No       | Runtime identifier                 |
| `environment`          | string          | "Dev"                    | No       | Environment name (Dev, Prod, etc.) |
| `integration`          | string          | "default_integration"    | No       | Integration name                   |
| `project`              | string          | "default_project"        | No       | Project name                       |

## Usage

Import the dependency to your source code:

```ballerina
import wso2/icp.runtime.bridge as _;

public function main() returns error? {
    // Configuration is automatically loaded from environment or Config.toml
    // The bridge initializes automatically and starts heartbeat monitoring
}
```

## Development

### Project Structure

```text
icp-runtime-bridge/
├── ballerina/              # Ballerina package source
│   ├── main.bal           # Main entry point and agent initialization
│   ├── icp_client.bal     # ICP HTTP client implementation
│   ├── status_monitor.bal # Artifact and status monitoring
│   ├── config.bal         # Configuration management
│   ├── security.bal       # JWT and authentication
│   └── types.bal          # Type definitions
├── native/                # Java native implementation
│   └── src/main/java/    # Java source files
├── ballerina-tests/       # Integration tests
└── build-config/          # Build configuration
```

### Code Quality

The project uses Checkstyle for code quality enforcement:

```bash
./gradlew checkstyleMain checkstyleTest
```

## Publishing Releases

The project uses GitHub Actions for automated releases. To create a new release:

1. Trigger the "Publish Release" workflow from GitHub Actions
2. Provide the release version (e.g., `1.0.0`)
3. Provide the next development version (e.g., `1.0.1-SNAPSHOT`)
4. Optionally enable "Publish to Ballerina Central"
5. Use "Dry Run" mode to test without publishing

The workflow will:

- Validate the version doesn't already exist
- Update version numbers in all files
- Build and publish to GitHub Packages
- Optionally publish to Ballerina Central
- Create a GitHub Release with artifacts
- Prepare the repository for next development iteration

## Contributing

We welcome contributions! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes with clear messages
4. Push to your branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Reporting Issues

To report bugs, request new features, or start discussions, visit the [WSO2 Integrator repository](https://github.com/wso2/product-integrator/issues).

### Code Style

- Follow Java and Ballerina coding conventions
- Ensure all tests pass before submitting PR
- Add tests for new features
- Update documentation as needed

## Support

- **Discord**: Chat with us on our [Discord server](https://discord.gg/wso2)
- **Stack Overflow**: Post questions with the [#wso2](https://stackoverflow.com/questions/tagged/wso2) tag
- **Issues**: Report bugs in the [issue tracker](https://github.com/wso2/product-integrator/issues)

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.

## Links

- [WSO2 Integration Control Plane](https://wso2.com/integration-platform)
- [Ballerina Language](https://ballerina.io/)
- [WSO2 Integrator](https://github.com/wso2/product-integrator)

---

Copyright © 2026 WSO2 LLC.
