FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

ARG BUILD_CONFIGURATION=Release

WORKDIR /src

COPY src/NoAsAService.Api/NoAsAService.Api.csproj ./src/NoAsAService.Api/
RUN dotnet restore ./src/NoAsAService.Api/NoAsAService.Api.csproj

COPY src/NoAsAService.Api/. ./src/NoAsAService.Api/
RUN dotnet publish ./src/NoAsAService.Api/NoAsAService.Api.csproj -c $BUILD_CONFIGURATION -o /app/publish --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS runtime

WORKDIR /app

RUN apk add --no-cache krb5-libs

ENV ASPNETCORE_URLS=http://+:8000

COPY --from=build /app/publish .

EXPOSE 8000

USER app

ENTRYPOINT ["dotnet", "NoAsAService.Api.dll"]
