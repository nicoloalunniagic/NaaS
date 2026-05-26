using Microsoft.EntityFrameworkCore;

namespace NoAsAService.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<Project> Projects => Set<Project>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(b =>
        {
            b.ToTable("users");
            b.HasKey(u => u.Id);
            b.Property(u => u.Username).IsRequired().HasMaxLength(64);
            b.Property(u => u.NormalizedUsername).IsRequired().HasMaxLength(64);
            b.Property(u => u.PasswordHash).IsRequired().HasMaxLength(512);
            b.HasIndex(u => u.NormalizedUsername).IsUnique();
        });

        modelBuilder.Entity<Customer>(b =>
        {
            b.ToTable("customers");
            b.HasKey(c => c.Id);
            b.Property(c => c.Name).IsRequired().HasMaxLength(200);
            b.Property(c => c.Email).HasMaxLength(320);
            b.Property(c => c.CodiceFiscale).IsRequired().HasMaxLength(16);
            b.HasIndex(c => c.Name);
            b.HasIndex(c => c.CodiceFiscale).IsUnique();
            b.HasIndex(c => new { c.Name, c.Email }).IsUnique();
        });

        modelBuilder.Entity<Project>(b =>
        {
            b.ToTable("projects");
            b.HasKey(p => p.Id);
            b.Property(p => p.Name).IsRequired().HasMaxLength(200);
            b.Property(p => p.Description).HasMaxLength(2000);
            b.Property(p => p.OwnerUserId).IsRequired(false);
            b.HasOne(p => p.Customer)
                .WithMany(c => c.Projects)
                .HasForeignKey(p => p.CustomerId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(p => p.CustomerId);
        });
    }
}
