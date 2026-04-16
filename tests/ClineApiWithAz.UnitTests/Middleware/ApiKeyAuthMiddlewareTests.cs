using System.Text.Json;
using ClineApiWithAz.Middleware;
using ClineApiWithAz.Models.Responses;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;

namespace ClineApiWithAz.UnitTests.Middleware;

public class ApiKeyAuthMiddlewareTests
{
    private const string ValidApiKey = "sk-test-valid";

    private static ApiKeyAuthMiddleware CreateMiddleware(RequestDelegate next, string? configuredKey = ValidApiKey)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ApiKey:Value"] = configuredKey
            })
            .Build();
        return new ApiKeyAuthMiddleware(next, config);
    }

    [Fact]
    public async Task 有効なAPIキーの場合_次のミドルウェアへ進む()
    {
        var nextCalled = false;
        var middleware = CreateMiddleware(_ => { nextCalled = true; return Task.CompletedTask; });
        var context = CreateHttpContext($"Bearer {ValidApiKey}");

        await middleware.InvokeAsync(context);

        Assert.True(nextCalled);
    }

    [Fact]
    public async Task 無効なAPIキーの場合_401を返し次のミドルウェアへ進まない()
    {
        var nextCalled = false;
        var middleware = CreateMiddleware(_ => { nextCalled = true; return Task.CompletedTask; });
        var context = CreateHttpContext("Bearer wrong-key");

        await middleware.InvokeAsync(context);

        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);

        var body = await ReadBodyAsync(context);
        var error = JsonSerializer.Deserialize<ErrorResponse>(body);
        Assert.Equal("invalid_api_key", error!.Error.Code);
    }

    [Fact]
    public async Task Authorizationヘッダーがない場合_401を返す()
    {
        var nextCalled = false;
        var middleware = CreateMiddleware(_ => { nextCalled = true; return Task.CompletedTask; });
        var context = CreateHttpContext(null);

        await middleware.InvokeAsync(context);

        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);
    }

    [Fact]
    public async Task Bearer以外のスキームの場合_401を返す()
    {
        var nextCalled = false;
        var middleware = CreateMiddleware(_ => { nextCalled = true; return Task.CompletedTask; });
        var context = CreateHttpContext("Basic dXNlcjpwYXNz");

        await middleware.InvokeAsync(context);

        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);
    }

    private static HttpContext CreateHttpContext(string? authHeader)
    {
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        if (authHeader is not null)
            context.Request.Headers.Authorization = authHeader;
        return context;
    }

    private static async Task<string> ReadBodyAsync(HttpContext context)
    {
        context.Response.Body.Seek(0, SeekOrigin.Begin);
        return await new StreamReader(context.Response.Body).ReadToEndAsync();
    }
}
