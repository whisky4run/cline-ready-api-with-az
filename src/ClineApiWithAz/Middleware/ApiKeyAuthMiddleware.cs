using System.Text.Json;
using ClineApiWithAz.Models.Responses;
using ClineApiWithAz.Services;

namespace ClineApiWithAz.Middleware;

public class ApiKeyAuthMiddleware(RequestDelegate next, IApiKeyService apiKeyService)
{
    // HttpContext.Items に格納するキー
    public const string MemberIdKey = "MemberId";
    public const string MemberNameKey = "MemberName";
    public const string MemberRoleKey = "MemberRole";
    public const string MemberEntraIdKey = "MemberEntraId";
    public const string MemberEmailKey = "MemberEmail";

    public async Task InvokeAsync(HttpContext context)
    {
        var authHeader = context.Request.Headers.Authorization.FirstOrDefault();
        if (authHeader is null || !authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            await WriteUnauthorizedAsync(context, "API key is required. Use 'Authorization: Bearer <api-key>'.");
            return;
        }

        var apiKey = authHeader["Bearer ".Length..].Trim();
        var member = await apiKeyService.ValidateAndGetMemberAsync(apiKey);
        if (member is null)
        {
            await WriteUnauthorizedAsync(context, "Invalid API key.");
            return;
        }

        context.Items[MemberIdKey] = member.Id;
        context.Items[MemberNameKey] = member.Name;
        context.Items[MemberRoleKey] = member.Role;
        context.Items[MemberEntraIdKey] = member.EntraId;
        context.Items[MemberEmailKey] = member.Email;

        await next(context);
    }

    private static async Task WriteUnauthorizedAsync(HttpContext context, string message)
    {
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        context.Response.ContentType = "application/json";
        var error = ErrorResponse.Create(message, "invalid_request_error", "invalid_api_key");
        await context.Response.WriteAsync(JsonSerializer.Serialize(error));
    }
}
