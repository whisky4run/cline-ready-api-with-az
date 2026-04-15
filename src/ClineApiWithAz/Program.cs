using Azure.Identity;
using ClineApiWithAz.Middleware;
using ClineApiWithAz.Services;
using Microsoft.Azure.Cosmos;

var builder = WebApplication.CreateBuilder(args);

// Azure Key Vault からシークレットを取得（本番環境のみ）
if (!builder.Environment.IsDevelopment())
{
    var keyVaultUri = builder.Configuration["KeyVault:Uri"];
    if (!string.IsNullOrEmpty(keyVaultUri))
    {
        builder.Configuration.AddAzureKeyVault(new Uri(keyVaultUri), new DefaultAzureCredential());
    }
}

// Cosmos DB クライアント（シングルトン）
builder.Services.AddSingleton<CosmosClient>(sp =>
{
    var connectionString = builder.Configuration["CosmosDb:ConnectionString"]
        ?? throw new InvalidOperationException("CosmosDb:ConnectionString が設定されていません");
    return new CosmosClient(connectionString, new CosmosClientOptions
    {
        SerializerOptions = new CosmosSerializationOptions
        {
            PropertyNamingPolicy = CosmosPropertyNamingPolicy.CamelCase
        }
    });
});

// サービス登録
builder.Services.AddScoped<IApiKeyService, CosmosApiKeyService>();
builder.Services.AddScoped<IUsageService, CosmosUsageService>();
builder.Services.AddSingleton<IAzureAIService, AzureAIService>();

builder.Services.AddControllers();

// Application Insights（設定されている場合のみ有効化）
var appInsightsConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
if (!string.IsNullOrEmpty(appInsightsConnectionString))
{
    builder.Services.AddApplicationInsightsTelemetry(options =>
    {
        options.ConnectionString = appInsightsConnectionString;
    });
}

var app = builder.Build();

app.UseHttpsRedirection();

// APIキー認証ミドルウェアを全エンドポイントに適用
app.UseMiddleware<ApiKeyAuthMiddleware>();

app.MapControllers();

app.Run();

// WebApplicationFactory からアクセスできるように公開
public partial class Program { }
