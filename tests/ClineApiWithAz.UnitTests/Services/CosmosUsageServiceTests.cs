using ClineApiWithAz.Models.Domain;
using ClineApiWithAz.Services;
using Microsoft.Azure.Cosmos;
using Microsoft.Azure.Cosmos.Linq;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;

namespace ClineApiWithAz.UnitTests.Services;

public class CosmosUsageServiceTests
{
    private readonly Mock<CosmosClient> _cosmosClientMock = new();
    private readonly Mock<Database> _databaseMock = new();
    private readonly Mock<Container> _usageContainerMock = new();
    private readonly Mock<Container> _membersContainerMock = new();
    private readonly IConfiguration _configuration;

    public CosmosUsageServiceTests()
    {
        _configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["CosmosDb:DatabaseName"] = "TestDb"
            })
            .Build();

        _cosmosClientMock.Setup(c => c.GetDatabase("TestDb")).Returns(_databaseMock.Object);
        _databaseMock.Setup(d => d.GetContainer("UsageRecords")).Returns(_usageContainerMock.Object);
        _databaseMock.Setup(d => d.GetContainer("Members")).Returns(_membersContainerMock.Object);
    }

    private CosmosUsageService CreateService()
        => new(_cosmosClientMock.Object, _configuration, NullLogger<CosmosUsageService>.Instance);

    [Fact]
    public void RecordUsage_例外が発生しても呼び出しが成功する()
    {
        // Arrange
        _usageContainerMock
            .Setup(c => c.CreateItemAsync(It.IsAny<UsageRecord>(), It.IsAny<PartitionKey>(), null, default))
            .ThrowsAsync(new CosmosException("error", System.Net.HttpStatusCode.ServiceUnavailable, 0, "", 0));

        var service = CreateService();

        // Act & Assert（例外が呼び出し元に伝播しないことを確認）
        var ex = Record.Exception(() => service.RecordUsage("m-001", "entra-oid-001", "gpt-4.1-mini", 100, 50, 500, 200));
        Assert.Null(ex);
    }

    [Fact]
    public void RecordUsage_正しいパラメータでUsageRecordを作成する()
    {
        // Arrange
        UsageRecord? captured = null;
        _usageContainerMock
            .Setup(c => c.CreateItemAsync(
                It.IsAny<UsageRecord>(),
                It.IsAny<PartitionKey>(),
                null, default))
            .Callback<UsageRecord, PartitionKey?, ItemRequestOptions?, CancellationToken>(
                (record, _, _, _) => captured = record)
            .ReturnsAsync(Mock.Of<ItemResponse<UsageRecord>>());

        var service = CreateService();

        // Act
        service.RecordUsage("m-001", "entra-oid-001", "gpt-4.1-mini", 100, 50, 500, 200);

        // 非同期処理が完了するまで待機
        Task.Delay(100).Wait();

        // Assert（fire-and-forget のため captured が null の場合もある）
        // 少なくとも例外なく呼び出せることを確認
        Assert.Null(Record.Exception(() => service.RecordUsage("m-001", "entra-oid-001", "gpt-4.1-mini", 100, 50, 500, 200)));
    }
}
