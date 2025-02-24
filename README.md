[![EF Migrations Action Test](https://github.com/yuki-nemurenai/ef-migrations-action/actions/workflows/test.yaml/badge.svg?branch=main)](https://github.com/yuki-nemurenai/ef-migrations-action/actions/workflows/test.yaml)

# EF Core Migrations GitHub Action

A GitHub Action for automating .NET Entity Framework Core migrations in your CI/CD pipeline. This action supports both single-database and multi-database scenarios, making it flexible for various application architectures.

## Features

- 🔄 Automatic detection and execution of pending migrations
- 📊 Support for multiple DbContext configurations
- 🎯 Flexible database connection management
- 📄 Detailed execution logs and results
- ⚡ Simple integration with existing workflows
- 📝 Generates a summary table of applied migrations

## Usage

### Basic Configuration (Single Database)

When all your DbContexts use the same database, use the `connection` parameter:

```yaml
- uses: yuki-nemurenai/ef-migrations-action@v1.0.0
  with:
    project: "src/YourProject/YourProject.csproj"
    connection: "Host=localhost;Port=5432;Database=postgres;Username=postgres;Password=postgres"
```

### Multiple Databases Configuration

When different DbContexts use different databases, use the `connections` parameter:

```yaml
- uses: yuki-nemurenai/ef-migrations-action@v1.0.0
  with:
    project: "src/YourProject/YourProject.csproj"
    connections: |
      MyDbContext1=Host=localhost;Port=5432;Database=postgres;Username=postgres;Password=postgres
      MyDbContext2=Host=localhost;Port=5432;Database=postgres;Username=postgres;Password=postgres
```

## Input Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `project` | Yes | Path to the project containing EF Core migrations |
| `connection` | No* | Single database connection string used for all contexts |
| `connections` | No* | Key-value pairs of DbContext names and their connection strings |

\* Either `connection` or `connections` must be provided

## Output Parameters

| Parameter | Description |
|-----------|-------------|
| `logs` | Detailed execution logs of the migration process |
| `result` | HTML table containing migration results for each context |

## Reference Example

```yaml
env:
  DOTNET_VERSION: 9.0.x
  PROJECT: src/MyApp.Data/MyApp.Data.csproj
jobs:
  migrations:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Setup dotnet
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: ${{ env.DOTNET_VERSION }}
    - name: Install EF Core CLI
      run: dotnet tool install dotnet-ef --global
    - name: Restore dependencies
      run: dotnet restore ${{ env.PROJECT }}
    - name: Dotnet build project
      run: dotnet build ${{ env.PROJECT }} --no-restore
    - name: Migrations
      id: ef-database-update
      uses: yuki-nemurenai/ef-migrations-action@v1.0.0
      with:
        project: ${{ env.PROJECT }}
        connections: |
          IdentityDbContext=${{ secrets.IDENTITY_DB_CONNECTION }}
          ApplicationDbContext=${{ secrets.APP_DB_CONNECTION }}
    - name: Migrations summary
      run: |
        { 
        echo "## Migrations Results Table :bookmark_tabs:"
        echo "${{ steps.ef-database-update.outputs.result }}"
        echo ""
        } >> $GITHUB_STEP_SUMMARY
```

## License

[MIT](LICENSE)
