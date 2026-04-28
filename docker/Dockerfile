FROM mcr.microsoft.com/dotnet/sdk:10.0-preview AS build

WORKDIR /src

COPY src/NoAsAService.Api/NoAsAService.Api.csproj ./src/NoAsAService.Api/
RUN dotnet restore ./src/NoAsAService.Api/NoAsAService.Api.csproj

COPY src/NoAsAService.Api/. ./src/NoAsAService.Api/
RUN dotnet publish ./src/NoAsAService.Api/NoAsAService.Api.csproj -c Release -o /app/publish --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-preview AS runtime

WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8000

COPY --from=build /app/publish .

EXPOSE 8000

USER app

ENTRYPOINT ["dotnet", "NoAsAService.Api.dll"]
