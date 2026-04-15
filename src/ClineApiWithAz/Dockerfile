# ─── ビルドステージ ───────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# 依存関係のリストア（レイヤーキャッシュを効かせる）
COPY src/ClineApiWithAz/ClineApiWithAz.csproj src/ClineApiWithAz/
RUN dotnet restore src/ClineApiWithAz/ClineApiWithAz.csproj

# ソースコードをコピーしてビルド
COPY src/ClineApiWithAz/ src/ClineApiWithAz/
RUN dotnet publish src/ClineApiWithAz/ClineApiWithAz.csproj \
    -c Release \
    -o /app/publish \
    --no-restore

# ─── ランタイムステージ ───────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# セキュリティ: 非 root ユーザーで実行
RUN adduser --disabled-password --gecos "" appuser
USER appuser

# ビルド成果物をコピー
COPY --from=build --chown=appuser:appuser /app/publish .

# Container Apps はポート 8080 を使用
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "ClineApiWithAz.dll"]
