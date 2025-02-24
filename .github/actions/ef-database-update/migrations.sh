#!/bin/bash

# Regular expression to extract only the JSON block from the dotnet ef command output.
declare json_regex="/^\[/{:a; p; n; /^\]$/!ba; p}"
# Regular expression to exclude lines that start with a timestamp in the format [HH:MM:SS].
declare exclude_timestamp_regex="^\[[0-2][0-9]:[0-5][0-9]:[0-5][0-9]"
# Declare an associative array for contexts and connections.
declare -A context_connections

# Lists available DbContext types.
get_dbcontexts() {
    local project=$1
    contexts=$(dotnet ef dbcontext list --json --no-build --project $project 2>&1)
    command_status=$?
    if [[ "$command_status" -ne 0 ]]; then
        echo "Error executing command: $contexts"
        return 1
    fi
    contexts_json=$(echo "$contexts" | sed -n "$json_regex")
    jq_len=$(echo "$contexts_json" | jq length)
    if [[ "$jq_len" -gt 0 ]]; then
        echo "$contexts_json"
    else
        echo "No DbContexts found"
        return 1
    fi
}

# Updates the database to the latest migration.
ef_database_update() {
    local project=$1
    local context=$2
    local connection="$3"
    ef_database_update=$(dotnet ef database update --project $project --no-build --context $context --connection "$connection" 2>&1)
    command_status=$?
    if [[ "$command_status" -ne 0 ]]; then
        echo "Error executing command: $ef_database_update"
        return 1
    fi
    echo "$ef_database_update"
}

# Lists available migrations.
get_migrations_list() {
    local project=$1
    local context=$2
    local connection="$3"
    migrations_list=$(dotnet ef migrations list --no-build --project $project --context $context --connection "$connection" --json 2>&1)
    command_status=$?
    if [[ "$command_status" -ne 0 ]]; then
        echo "Error executing command: $migrations_list"
        return 1
    fi
    migrations_list_json=$(echo "$migrations_list" | grep -v "$exclude_timestamp_regex" |sed -n "$json_regex")
    jq_len=$(echo "$migrations_list_json" | jq length)
    if [[ "$jq_len" -gt 0 ]]; then
        echo "$migrations_list_json"
    else
        echo "No migrations found"
        return 1
    fi
}

contexts_raw=$(get_dbcontexts "$project")
if [[ $? -ne 0 ]]; then
    echo "::error::Failed to retrieve DbContexts"
    exit 1
fi

echo "::group::DbContexts"
echo "$contexts_raw"
echo "::endgroup::"

# Extracts the DbContext names from the JSON output.
contexts=$(echo "$contexts_raw" | jq -r '.[].name')

if [[ -n "$connection" ]]; then
    echo "Single DB connection provided. Using it for all contexts."
    for context in $contexts; do
        context_connections["$context"]="$connection"
    done
elif [[ -n "$connections" ]]; then
    echo "Multiple DB connections provided. Using associative array for connections and contexts."
    while IFS=$'\n' read -r line; do
        key="${line%%=*}"
        value="${line#*=}"
        if [[ -n $key ]]; then context_connections["$key"]="$value"; fi
    done <<< "$connections"
else
    echo "::error::No connection or connections provided."
    exit 1
fi
# Begins the HTML table.
migrations_result_html_table="<table><tr><th>Database Context</th><th>Migration Name</th><th>Status</th></tr>"
merged_migrations_list_output_raw=""
# Flag to indicate if there was an error.
has_error=false
# Logs for each migration.
migration_logs=""

for context in $contexts; do
    connection="${context_connections["$context"]}"
    if [[ -z "$connection" ]]; then
        echo "::error::No connection string provided for context $context"
        exit 1
    fi

    migration_logs+="------------------------------------"$'\n'
    migration_logs+="Running migrations for $context"$'\n'
    migration_logs+="------------------------------------"$'\n'

    # Updates the database to the latest migration for the given context.
    ef_database_update_raw=$(ef_database_update "$project" "$context" "$connection")
    if [[ $? -ne 0 ]]; then
        echo "::error::EF database update failed for context $context"
        echo "$ef_database_update_raw"
        exit 1
    fi
    migration_logs+="$ef_database_update_raw"$'\n'
    # Fills the HTML table with the migration status.
    migration_rows=""
    
    migrations_list_output_json=$(get_migrations_list "$project" "$context" "$connection")
    if [[ $? -ne 0 ]]; then
        echo "::error::Failed to list migrations for context $context"
        echo "$migrations_list_output_json"
        exit 1
    fi
    
    echo "::group::Migrations list JSON $context"
    echo "$migrations_list_output_json"
    echo "::endgroup::"
    merged_migrations_list_output_raw+="$migrations_list_output_json"
    # Count the number of migrations.
    migration_count=$(echo "$migrations_list_output_json" | jq length)

    migration_list_output=$(echo "$migrations_list_output_json" | jq -c '.[]')
    while read -r migration; do
    migration_name=$(echo "$migration" | jq -r '.name')
    migration_applied=$(echo "$migration" | jq -r '.applied')
    case "$migration_applied" in
        "true")
        if [[ -n $(echo "$ef_database_update_raw" | grep "$migration_name") ]]; then
            migration_rows+="<tr><td>$migration_name</td><td>Successfully applied :white_check_mark:</td></tr>"
        else
            migration_rows+="<tr><td>$migration_name</td><td>Already applied :ballot_box_with_check:</td></tr>"
        fi
        ;;
        "false")
        if [[ -n $(echo "$ef_database_update_raw" | grep "$migration_name") ]]; then
            migration_rows+="<tr><td>$migration_name</td><td>Failed :x:</td></tr>"
            has_error=true
        else
            migration_rows+="<tr><td>$migration_name</td><td>Migration is pending :clock10:</td></tr>"
        fi
        ;;
    esac
    done <<< "$migration_list_output"
    
    if [ $migration_count -gt 0 ]; then
    migrations_result_html_table+="<tr><td rowspan=\"$migration_count\">$context</td>${migration_rows:4}"
    fi
done

# Ends the HTML table.
migrations_result_html_table+="</table>"
echo "::group::Migrations logs"
echo "$migration_logs"
echo "::endgroup::"

{
    echo "logs<<EOF"
    echo "$migration_logs"
    echo "EOF"
} >> $GITHUB_OUTPUT

echo "result=$migrations_result_html_table" >> $GITHUB_OUTPUT

if [ "$has_error" = true ]; then
    exit 1
fi