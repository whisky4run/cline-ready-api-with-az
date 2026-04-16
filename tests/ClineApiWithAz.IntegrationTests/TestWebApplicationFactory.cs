using ClineApiWithAz.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Moq;

namespace ClineApiWithAz.IntegrationTests;

/// <summary>統合テスト用の WebApplicationFactory。AI Foundry をモックに差し替える。</summary>
public class TestWebApplicationFactory : WebApplicationFactory<Program>
{
    public const string TestApiKey = "sk-integration-test";

    public Mock<IAzureAIService> AiServiceMock { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IAzureAIService>();
            services.AddSingleton(AiServiceMock.Object);
        });

        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ApiKey:Value"] = TestApiKey,
                ["AzureAI:Endpoint"] = "https://test.inference.ai.azure.com",
                ["AzureAI:ApiKey"] = "test-ai-key",
                ["AzureAI:Models:gpt-4.1-mini"] = "azureml://registries/azure-openai/models/gpt-4.1-mini/versions/2025-04-14"
            });
        });
    }
}
