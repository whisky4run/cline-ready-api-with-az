using ClineApiWithAz.Middleware;
using ClineApiWithAz.Services;

var builder = WebApplication.CreateBuilder(args);

// サービス登録
builder.Services.AddSingleton<IAzureAIService, AzureAIService>();

builder.Services.AddControllers();

var app = builder.Build();

app.UseHttpsRedirection();

// APIキー認証ミドルウェアを全エンドポイントに適用
app.UseMiddleware<ApiKeyAuthMiddleware>();

app.MapControllers();

app.Run();

// WebApplicationFactory からアクセスできるように公開
public partial class Program { }
