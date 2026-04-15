using ClineApiWithAz.Models.Domain;
using ClineApiWithAz.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Moq;

namespace ClineApiWithAz.IntegrationTests;

/// <summary>統合テスト用の WebApplicationFactory。AI Foundry・Cosmos DB をモックに差し替える。</summary>
public class TestWebApplicationFactory : WebApplicationFactory<Program>
{
    public Mock<IApiKeyService> ApiKeyServiceMock { get; } = new();
    public Mock<IAzureAIService> AiServiceMock { get; } = new();
    public Mock<IUsageService> UsageServiceMock { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureServices(services =>
        {
            // 実装を削除してモックに差し替え
            services.RemoveAll<IApiKeyService>();
            services.RemoveAll<IAzureAIService>();
            services.RemoveAll<IUsageService>();

            services.AddSingleton(ApiKeyServiceMock.Object);
            services.AddSingleton(AiServiceMock.Object);
            services.AddSingleton(UsageServiceMock.Object);
        });

        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["AzureAI:Endpoint"] = "https://test.inference.ai.azure.com",
                ["AzureAI:ApiKey"] = "test-ai-key",
                ["AzureAI:Models:gpt-4.1-mini"] = "azureml://registries/azure-openai/models/gpt-4.1-mini/versions/2025-04-14",
                ["CosmosDb:ConnectionString"] = "AccountEndpoint=https://test.documents.azure.com:443/;AccountKey=dGVzdA==;",
                ["CosmosDb:DatabaseName"] = "TestDb"
            });
        });
    }

    /// <summary>テスト用メンバーを返すように ApiKeyService を設定する</summary>
    public void SetupMember(string apiKey, Member member)
    {
        ApiKeyServiceMock
            .Setup(s => s.ValidateAndGetMemberAsync(apiKey))
            .ReturnsAsync(member);
    }

    /// <summary>認証失敗を返すように設定する</summary>
    public void SetupInvalidApiKey(string apiKey)
    {
        ApiKeyServiceMock
            .Setup(s => s.ValidateAndGetMemberAsync(apiKey))
            .ReturnsAsync((Member?)null);
    }
}
