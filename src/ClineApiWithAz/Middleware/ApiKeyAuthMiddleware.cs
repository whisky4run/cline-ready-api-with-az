using System.Text.Json;
using ClineApiWithAz.Models.Responses;

namespace ClineApiWithAz.Middleware;

public class ApiKeyAuthMiddleware(RequestDelegate next, IConfiguration configuration)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var authHeader = context.Request.Headers.Authorization.FirstOrDefault();
        if (authHeader is null || !authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            await WriteUnauthorizedAsync(context, "API key is required. Use 'Authorization: Bearer <api-key>'.");
            return;
        }

        var apiKey = authHeader["Bearer ".Length..].Trim();
        var expectedKey = configuration["ApiKey:Value"];

        if (string.IsNullOrEmpty(expectedKey) || apiKey != expectedKey)
        {
            await WriteUnauthorizedAsync(context, "Invalid API key.");
            return;
        }

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
