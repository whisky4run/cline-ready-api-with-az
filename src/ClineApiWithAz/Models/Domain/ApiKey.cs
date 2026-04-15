namespace ClineApiWithAz.Models.Domain;

public class ApiKey
{
    public string Id { get; set; } = string.Empty;
    /// <summary>パーティションキー</summary>
    public string MemberId { get; set; } = string.Empty;
    /// <summary>SHA-256 ハッシュ（生のキーは保存しない）</summary>
    public string KeyHash { get; set; } = string.Empty;
    /// <summary>識別用プレフィックス（例: sk-alice-）</summary>
    public string Prefix { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastUsedAt { get; set; }
}
