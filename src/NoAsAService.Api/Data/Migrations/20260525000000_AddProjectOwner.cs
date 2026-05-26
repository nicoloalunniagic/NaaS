using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NoAsAService.Api.Data.Migrations
{
    /// <summary>
    /// Adds OwnerUserId (nullable) to the projects table.
    /// Used for the IDOR / Broken Access Control VAPT lab demonstration.
    /// Uses IF NOT EXISTS so the migration is safe to apply against databases
    /// that were previously created via EnsureCreated with the new model.
    /// </summary>
    public partial class AddProjectOwner : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(@"
                ALTER TABLE projects ADD COLUMN IF NOT EXISTS ""OwnerUserId"" integer;
            ");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "OwnerUserId",
                table: "projects");
        }
    }
}
