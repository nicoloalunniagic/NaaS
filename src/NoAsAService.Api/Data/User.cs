using System.ComponentModel.DataAnnotations;

namespace NoAsAService.Api.Data;

public class User
{
    public int Id { get; set; }

    [Required]
    [MaxLength(64)]
    public string Username { get; set; } = string.Empty;

    [Required]
    [MaxLength(64)]
    public string NormalizedUsername { get; set; } = string.Empty;

    [Required]
    [MaxLength(512)]
    public string PasswordHash { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
