FROM mcr.microsoft.com/dotnet/sdk:10.0-preview AS build

WORKDIR /src

COPY src/NoAsAService.Api.csproj ./src/
RUN dotnet restore ./src/NoAsAService.Api.csproj

COPY src/. ./src/
RUN dotnet publish ./src/NoAsAService.Api.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-preview AS runtime

WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8000

RUN apt-get update \
    && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8000/ > /dev/null 2>&1 || exit 1

USER app

ENTRYPOINT ["dotnet", "NoAsAService.Api.dll"]
