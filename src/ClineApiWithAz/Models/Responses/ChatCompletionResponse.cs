using System.Text.Json.Serialization;

namespace ClineApiWithAz.Models.Responses;

public class ChatCompletionResponse
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("object")]
    public string Object { get; set; } = "chat.completion";

    [JsonPropertyName("created")]
    public long Created { get; set; } = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

    [JsonPropertyName("model")]
    public string Model { get; set; } = string.Empty;

    [JsonPropertyName("choices")]
    public List<ChatCompletionChoice> Choices { get; set; } = [];

    [JsonPropertyName("usage")]
    public UsageInfo? Usage { get; set; }
}

public class ChatCompletionChoice
{
    [JsonPropertyName("index")]
    public int Index { get; set; }

    [JsonPropertyName("message")]
    public ChatCompletionMessage Message { get; set; } = new();

    [JsonPropertyName("finish_reason")]
    public string? FinishReason { get; set; }
}

public class ChatCompletionMessage
{
    [JsonPropertyName("role")]
    public string Role { get; set; } = "assistant";

    [JsonPropertyName("content")]
    public string? Content { get; set; }
}

public class UsageInfo
{
    [JsonPropertyName("prompt_tokens")]
    public int PromptTokens { get; set; }

    [JsonPropertyName("completion_tokens")]
    public int CompletionTokens { get; set; }

    [JsonPropertyName("total_tokens")]
    public int TotalTokens { get; set; }
}

// ストリーミング用チャンク
public class ChatCompletionChunk
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("object")]
    public string Object { get; set; } = "chat.completion.chunk";

    [JsonPropertyName("created")]
    public long Created { get; set; } = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

    [JsonPropertyName("model")]
    public string Model { get; set; } = string.Empty;

    [JsonPropertyName("choices")]
    public List<ChatCompletionChunkChoice> Choices { get; set; } = [];

    [JsonPropertyName("usage")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public UsageInfo? Usage { get; set; }
}

public class ChatCompletionChunkChoice
{
    [JsonPropertyName("index")]
    public int Index { get; set; }

    [JsonPropertyName("delta")]
    public ChatCompletionDelta Delta { get; set; } = new();

    [JsonPropertyName("finish_reason")]
    public string? FinishReason { get; set; }
}

public class ChatCompletionDelta
{
    [JsonPropertyName("role")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Role { get; set; }

    [JsonPropertyName("content")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Content { get; set; }
}
