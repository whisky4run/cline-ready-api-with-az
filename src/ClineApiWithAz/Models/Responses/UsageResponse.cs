using System.Text.Json.Serialization;

namespace ClineApiWithAz.Models.Responses;

public class UsageSummaryListResponse
{
    [JsonPropertyName("object")]
    public string Object { get; set; } = "list";

    [JsonPropertyName("data")]
    public List<UsageSummary> Data { get; set; } = [];
}

public class UsageSummary
{
    [JsonPropertyName("member_id")]
    public string MemberId { get; set; } = string.Empty;

    [JsonPropertyName("member_name")]
    public string MemberName { get; set; } = string.Empty;

    [JsonPropertyName("entra_id")]
    public string EntraId { get; set; } = string.Empty;

    [JsonPropertyName("email")]
    public string Email { get; set; } = string.Empty;

    [JsonPropertyName("total_prompt_tokens")]
    public long TotalPromptTokens { get; set; }

    [JsonPropertyName("total_completion_tokens")]
    public long TotalCompletionTokens { get; set; }

    [JsonPropertyName("total_tokens")]
    public long TotalTokens { get; set; }

    [JsonPropertyName("request_count")]
    public long RequestCount { get; set; }
}

public class MyUsageResponse : UsageSummary
{
    [JsonPropertyName("period")]
    public UsagePeriod? Period { get; set; }
}

public class UsagePeriod
{
    [JsonPropertyName("from")]
    public string From { get; set; } = string.Empty;

    [JsonPropertyName("to")]
    public string To { get; set; } = string.Empty;
}
