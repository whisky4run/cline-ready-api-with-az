namespace ClineApiWithAz.Models.Domain;

public class UsageRecord
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    /// <summary>パーティションキー</summary>
    public string MemberId { get; set; } = string.Empty;
    /// <summary>Entra ID の Object ID（使用量を Entra ID ユーザーで直接集計するために保持）</summary>
    public string EntraId { get; set; } = string.Empty;
    public DateTime RequestedAt { get; set; } = DateTime.UtcNow;
    public string Model { get; set; } = string.Empty;
    public int PromptTokens { get; set; }
    public int CompletionTokens { get; set; }
    public int TotalTokens { get; set; }
    public long DurationMs { get; set; }
    public int StatusCode { get; set; }
}
