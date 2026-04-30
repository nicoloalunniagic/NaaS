using System.ComponentModel.DataAnnotations;

namespace NoAsAService.Api.Data;

public class Customer
{
    public int Id { get; set; }

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(320)]
    public string? Email { get; set; }

    [Required]
    [MaxLength(16)]
    [MinLength(16)]
    public string CodiceFiscale { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public List<Project> Projects { get; set; } = new();
}
