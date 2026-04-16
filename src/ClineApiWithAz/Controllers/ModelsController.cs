using ClineApiWithAz.Models.Responses;
using Microsoft.AspNetCore.Mvc;

namespace ClineApiWithAz.Controllers;

[ApiController]
[Route("v1")]
public class ModelsController(IConfiguration configuration) : ControllerBase
{
    [HttpGet("models")]
    public IActionResult GetModels()
    {
        var modelMappings = configuration.GetSection("AzureAI:Models")
            .Get<Dictionary<string, string>>() ?? [];

        // AzureAI:Models が空の場合は AzureAI:ModelName（環境変数 AzureAI__ModelName）をフォールバック
        IEnumerable<string> modelIds = modelMappings.Count > 0
            ? modelMappings.Keys
            : new[] { configuration["AzureAI:ModelName"] ?? string.Empty };

        var data = modelIds
            .Where(id => !string.IsNullOrEmpty(id))
            .Select(modelId => new ModelInfo
            {
                Id = modelId,
                Created = 1744588800, // 2025-04-14 UTC
                OwnedBy = "azure-ai-foundry"
            }).ToList();

        return Ok(new ModelsResponse { Data = data });
    }
}
