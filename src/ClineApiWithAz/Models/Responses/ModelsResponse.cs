using System.Text.Json.Serialization;

namespace ClineApiWithAz.Models.Responses;

public class ModelsResponse
{
    [JsonPropertyName("object")]
    public string Object { get; set; } = "list";

    [JsonPropertyName("data")]
    public List<ModelInfo> Data { get; set; } = [];
}

public class ModelInfo
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("object")]
    public string Object { get; set; } = "model";

    [JsonPropertyName("created")]
    public long Created { get; set; }

    [JsonPropertyName("owned_by")]
    public string OwnedBy { get; set; } = "azure-ai-foundry";
}
