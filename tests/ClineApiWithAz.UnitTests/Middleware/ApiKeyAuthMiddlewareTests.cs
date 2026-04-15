using System.Text.Json;
using ClineApiWithAz.Middleware;
using ClineApiWithAz.Models.Domain;
using ClineApiWithAz.Models.Responses;
using ClineApiWithAz.Services;
using Microsoft.AspNetCore.Http;
using Moq;

namespace ClineApiWithAz.UnitTests.Middleware;

public class ApiKeyAuthMiddlewareTests
{
    private readonly Mock<IApiKeyService> _apiKeyServiceMock = new();

    private ApiKeyAuthMiddleware CreateMiddleware(RequestDelegate next)
        => new(next, _apiKeyServiceMock.Object);

    [Fact]
    public async Task 有効なAPIキーの場合_次のミドルウェアへ進みメンバー情報をItemsに格納する()
    {
        // Arrange
        var member = new Member { Id = "m-001", Name = "Alice", Role = "member", IsActive = true };
        _apiKeyServiceMock
            .Setup(s => s.ValidateAndGetMemberAsync("valid-key"))
            .ReturnsAsync(member);

        var nextCalled = false;
        var middleware = CreateMiddleware(_ => { nextCalled = true; return Task.CompletedTask; });
        var context = CreateHttpContext("Bearer valid-key");

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        Assert.True(nextCalled);
        Assert.Equal("m-001", context.Items[ApiKeyAuthMiddleware.MemberIdKey]);
        Assert.Equal("Alice", context.Items[ApiKeyAuthMiddleware.MemberNameKey]);
        Assert.Equal("member", context.Items[ApiKeyAuthMiddleware.MemberRoleKey]);
    }

    [Fact]
    public async Task 無効なAPIキーの場合_401を返し次のミドルウェアへ進まない()
    {
        // Arrange
        _apiKeyServiceMock
            .Setup(s => s.ValidateAndGetMemberAsync(It.IsAny<string>()))
            .ReturnsAsync((Member?)null);

        var nextCalled = false;
        var middleware = CreateMiddleware(_ => { nextCalled = true; return Task.CompletedTask; });
        var context = CreateHttpContext("Bearer invalid-key");

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);

        var body = await ReadBodyAsync(context);
        var error = JsonSerializer.Deserialize<ErrorResponse>(body);
        Assert.Equal("invalid_api_key", error!.Error.Code);
    }

    [Fact]
    public async Task Authorizationヘッダーがない場合_401を返す()
    {
        // Arrange
        var nextCalled = false;
        var middleware = CreateMiddleware(_ => { nextCalled = true; return Task.CompletedTask; });
        var context = CreateHttpContext(null);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);
    }

    [Fact]
    public async Task Bearer以外のスキームの場合_401を返す()
    {
        // Arrange
        var nextCalled = false;
        var middleware = CreateMiddleware(_ => { nextCalled = true; return Task.CompletedTask; });
        var context = CreateHttpContext("Basic dXNlcjpwYXNz");

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status401Unauthorized, context.Response.StatusCode);
    }

    [Fact]
    public async Task 管理者ロールの場合_roleがadminとしてItemsに格納される()
    {
        // Arrange
        var admin = new Member { Id = "m-admin", Name = "Admin", Role = "admin", IsActive = true };
        _apiKeyServiceMock
            .Setup(s => s.ValidateAndGetMemberAsync("admin-key"))
            .ReturnsAsync(admin);

        var middleware = CreateMiddleware(_ => Task.CompletedTask);
        var context = CreateHttpContext("Bearer admin-key");

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        Assert.Equal("admin", context.Items[ApiKeyAuthMiddleware.MemberRoleKey]);
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
