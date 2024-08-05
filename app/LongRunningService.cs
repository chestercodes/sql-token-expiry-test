using Microsoft.Data.SqlClient;

public class DatabaseConfig
{
    public string ConnectionString { get; set; }

    public DatabaseConfig(string v)
    {
        ConnectionString = v;
    }
}

public class LongRunningService : BackgroundService
{
    private readonly ILogger<LongRunningService> logger;
    private readonly DatabaseConfig databaseConfig;

    public LongRunningService(ILogger<LongRunningService> logger, DatabaseConfig databaseConfig)
    {
        this.logger = logger;
        this.databaseConfig = databaseConfig;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            logger.LogInformation("Started service");
            var connectionString = databaseConfig.ConnectionString;
            var connection = new SqlConnection(connectionString);
            logger.LogInformation($"Opening connection with string {connectionString}");
            connection.Open();
            logger.LogInformation("Opened connection");

            var start = DateTime.UtcNow;

            while (true)
            {
                var now = DateTime.UtcNow;
                var nowString = now.ToString("o");
                var diff = Convert.ToInt32((now - start).TotalMinutes);

                const string sql = "SELECT NEWID();";

                try
                {
                    using var sqlCommand = new SqlCommand(sql, connection);
                    using var reader = sqlCommand.ExecuteReader();
                    while (reader.Read())
                    {
                        var guidFromServer = reader.GetGuid(0);
                        var logLine = $"Time is {nowString}, has been ~{diff} mins - ~{Convert.ToInt32(diff / 60.0)} hours. Guid from server is {guidFromServer}";
                        logger.LogInformation(logLine);
                    }
                }
                catch (Exception ex)
                {
                    logger.LogInformation(ex, "Failed on query");
                    logger.LogError(ex, "Failed on query");
                }

                var toWait = 20 * 60 * 1000;
                await Task.Delay(toWait);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to start");
            Console.WriteLine(ex.ToString());
        }
    }
}