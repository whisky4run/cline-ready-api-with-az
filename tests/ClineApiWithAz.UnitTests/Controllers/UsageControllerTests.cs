using ClineApiWithAz.Controllers;
using ClineApiWithAz.Middleware;
using ClineApiWithAz.Models.Responses;
using ClineApiWithAz.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moq;

namespace ClineApiWithAz.UnitTests.Controllers;

public class UsageControllerTests
{
    private readonly Mock<IUsageService> _usageServiceMock = new();

    private UsageController CreateController(string memberId = "m-001", string role = "member")
    {
        var controller = new UsageController(_usageServiceMock.Object);
        var context = new DefaultHttpContext();
        context.Items[ApiKeyAuthMiddleware.MemberIdKey] = memberId;
        context.Items[ApiKeyAuthMiddleware.MemberNameKey] = "Alice";
        context.Items[ApiKeyAuthMiddleware.MemberRoleKey] = role;
        context.Items[ApiKeyAuthMiddleware.MemberEntraIdKey] = "entra-oid-001";
        context.Items[ApiKeyAuthMiddleware.MemberEmailKey] = "alice@example.com";
        controller.ControllerContext = new ControllerContext { HttpContext = context };
        return controller;
    }

    [Fact]
    public async Task GetMyUsage_自分の使用量を返す()
    {
        // Arrange
        _usageServiceMock
            .Setup(s => s.GetUsageSummaryAsync("m-001", "Alice", "entra-oid-001", "alice@example.com", It.IsAny<DateTime>(), It.IsAny<DateTime>()))
            .ReturnsAsync(new UsageSummary
            {
                MemberId = "m-001",
                MemberName = "Alice",
                EntraId = "entra-oid-001",
                Email = "alice@example.com",
                TotalPromptTokens = 1000,
                TotalCompletionTokens = 500,
                TotalTokens = 1500,
                RequestCount = 10
            });

        var controller = CreateController("m-001");

        // Act
        var result = await controller.GetMyUsage(null, null);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<MyUsageResponse>(okResult.Value);
        Assert.Equal("m-001", response.MemberId);
        Assert.Equal(1500, response.TotalTokens);
        Assert.NotNull(response.Period);
    }

    [Fact]
    public async Task GetAllUsage_一般メンバーの場合_403を返す()
    {
        // Arrange
        var controller = CreateController("m-001", "member");

        // Act
        var result = await controller.GetAllUsage(null, null, null);

        // Assert
        var objectResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(403, objectResult.StatusCode);
        var error = Assert.IsType<ErrorResponse>(objectResult.Value);
        Assert.Equal("permission_denied", error.Error.Code);
    }

    [Fact]
    public async Task GetAllUsage_管理者の場合_全メンバーの使用量を返す()
    {
        // Arrange
        _usageServiceMock
            .Setup(s => s.GetAllUsageSummariesAsync(It.IsAny<DateTime>(), It.IsAny<DateTime>(), null))
            .ReturnsAsync([
                new UsageSummary { MemberId = "m-001", MemberName = "Alice", TotalTokens = 1000 },
                new UsageSummary { MemberId = "m-002", MemberName = "Bob", TotalTokens = 500 }
            ]);

        var controller = CreateController("m-admin", "admin");

        // Act
        var result = await controller.GetAllUsage(null, null, null);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<UsageSummaryListResponse>(okResult.Value);
        Assert.Equal(2, response.Data.Count);
    }

    [Fact]
    public async Task GetAllUsage_member_idパラメータを指定すると特定メンバーのみ返す()
    {
        // Arrange
        _usageServiceMock
            .Setup(s => s.GetAllUsageSummariesAsync(It.IsAny<DateTime>(), It.IsAny<DateTime>(), "m-001"))
            .ReturnsAsync([
                new UsageSummary { MemberId = "m-001", MemberName = "Alice", TotalTokens = 1000 }
            ]);

        var controller = CreateController("m-admin", "admin");

        // Act
        var result = await controller.GetAllUsage(null, null, "m-001");

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<UsageSummaryListResponse>(okResult.Value);
        Assert.Single(response.Data);
        Assert.Equal("m-001", response.Data[0].MemberId);
    }
}
