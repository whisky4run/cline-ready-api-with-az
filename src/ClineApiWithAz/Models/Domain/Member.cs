namespace ClineApiWithAz.Models.Domain;

public class Member
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    /// <summary>"member" または "admin"</summary>
    public string Role { get; set; } = "member";
    /// <summary>Entra ID の Object ID（ユーザー管理の紐付けに使用）</summary>
    public string EntraId { get; set; } = string.Empty;
    /// <summary>Entra ID に登録されたメールアドレス</summary>
    public string Email { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public bool IsAdmin => Role == "admin";
}
