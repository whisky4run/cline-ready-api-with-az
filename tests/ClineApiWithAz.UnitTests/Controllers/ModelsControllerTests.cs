using ClineApiWithAz.Controllers;
using ClineApiWithAz.Models.Responses;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;

namespace ClineApiWithAz.UnitTests.Controllers;

public class ModelsControllerTests
{
    private static ModelsController CreateController(Dictionary<string, string?> settings)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(settings)
            .Build();
        return new ModelsController(config);
    }

    [Fact]
    public void GetModels_設定されたモデル一覧を返す()
    {
        // Arrange
        var controller = CreateController(new()
        {
            ["AzureAI:Models:gpt-4.1-mini"] = "azureml://registries/azure-openai/models/gpt-4.1-mini/versions/2025-04-14"
        });

        // Act
        var result = controller.GetModels();

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<ModelsResponse>(okResult.Value);
        Assert.Single(response.Data);
        Assert.Equal("gpt-4.1-mini", response.Data[0].Id);
        Assert.Equal("azure-ai-foundry", response.Data[0].OwnedBy);
    }

    [Fact]
    public void GetModels_モデル設定がない場合_空リストを返す()
    {
        // Arrange
        var controller = CreateController(new());

        // Act
        var result = controller.GetModels();

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<ModelsResponse>(okResult.Value);
        Assert.Empty(response.Data);
    }

    [Fact]
    public void GetModels_複数モデルが設定されている場合_すべて返す()
    {
        // Arrange
        var controller = CreateController(new()
        {
            ["AzureAI:Models:gpt-4.1-mini"] = "azureml://...",
            ["AzureAI:Models:gpt-4o"] = "azureml://..."
        });

        // Act
        var result = controller.GetModels();

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<ModelsResponse>(okResult.Value);
        Assert.Equal(2, response.Data.Count);
    }
}
