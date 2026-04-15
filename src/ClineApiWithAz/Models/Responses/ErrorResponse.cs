using System.Text.Json.Serialization;

namespace ClineApiWithAz.Models.Responses;

public class ErrorResponse
{
    [JsonPropertyName("error")]
    public ErrorDetail Error { get; set; } = new();

    public static ErrorResponse Create(string message, string type, string code)
        => new() { Error = new ErrorDetail { Message = message, Type = type, Code = code } };
}

public class ErrorDetail
{
    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;

    [JsonPropertyName("type")]
    public string Type { get; set; } = string.Empty;

    [JsonPropertyName("code")]
    public string Code { get; set; } = string.Empty;
}
