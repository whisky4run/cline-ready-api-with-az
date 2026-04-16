using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClineApiWithAz.Models.Requests;

public class ChatCompletionRequest
{
    [JsonPropertyName("model")]
    public string Model { get; set; } = string.Empty;

    [JsonPropertyName("messages")]
    public List<ChatMessage> Messages { get; set; } = [];

    [JsonPropertyName("stream")]
    public bool Stream { get; set; } = false;

    [JsonPropertyName("temperature")]
    public float? Temperature { get; set; }

    [JsonPropertyName("max_tokens")]
    public int? MaxTokens { get; set; }

    [JsonPropertyName("top_p")]
    public float? TopP { get; set; }

    [JsonPropertyName("frequency_penalty")]
    public float? FrequencyPenalty { get; set; }

    [JsonPropertyName("presence_penalty")]
    public float? PresencePenalty { get; set; }
}

public class ChatMessage
{
    [JsonPropertyName("role")]
    public string Role { get; set; } = string.Empty;

    /// <summary>
    /// content は文字列または配列（マルチモーダル形式）の両方を受け付ける。
    /// Cline は [{"type":"text","text":"..."}] 形式で送信することがある。
    /// </summary>
    [JsonPropertyName("content")]
    public JsonElement Content { get; set; }

    /// <summary>content からテキストを取り出す。配列形式の場合は type=text の要素を結合する。</summary>
    public string GetTextContent()
    {
        return Content.ValueKind switch
        {
            JsonValueKind.String => Content.GetString() ?? string.Empty,
            JsonValueKind.Array => string.Concat(
                Content.EnumerateArray()
                    .Where(e => e.TryGetProperty("type", out var t) && t.GetString() == "text")
                    .Select(e => e.TryGetProperty("text", out var txt) ? txt.GetString() ?? string.Empty : string.Empty)),
            _ => string.Empty
        };
    }
}
