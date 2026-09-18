using System;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using FluentValidation;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using SmiApi.DTOs;
using SmiApi.Models;
using SmiApi.Repositories;

namespace SmiApi.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Roles = "ADMIN")] // Únicamente administradores de red pueden ver o alterar personal
public class UsuariosController : ControllerBase
{
    private readonly IUserRepository _userRepository;
    private readonly IValidator<CreateUserRequest> _createUserValidator;
    private readonly IValidator<UpdateUserRequest> _updateUserValidator;

    public UsuariosController(
        IUserRepository userRepository, 
        IValidator<CreateUserRequest> createUserValidator,
        IValidator<UpdateUserRequest> updateUserValidator)
    {
        _userRepository = userRepository;
        _createUserValidator = createUserValidator;
        _updateUserValidator = updateUserValidator;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var users = await _userRepository.GetAllAsync();
        var response = users.Select(u => new UserResponse
        {
            Id = u.Id,
            Username = u.Username,
            NombreCompleto = u.NombreCompleto,
            Email = u.Email,
            Rol = u.Rol,
            Activo = u.Activo,
            FechaCreacion = u.FechaCreacion
        });
        return Ok(response);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var user = await _userRepository.GetByIdAsync(id);
        if (user == null)
        {
            return NotFound(new { Message = "El usuario solicitado no existe." });
        }

        return Ok(new UserResponse
        {
            Id = user.Id,
            Username = user.Username,
            NombreCompleto = user.NombreCompleto,
            Email = user.Email,
            Rol = user.Rol,
            Activo = user.Activo,
            FechaCreacion = user.FechaCreacion
        });
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateUserRequest request)
    {
        // 1. Validar solicitud
        var validationResult = await _createUserValidator.ValidateAsync(request);
        if (!validationResult.IsValid)
        {
            return BadRequest(new { Errors = validationResult.Errors.Select(e => e.ErrorMessage) });
        }

        // 2. Validar que el username no esté duplicado
        var existingUser = await _userRepository.GetByUsernameAsync(request.Username);
        if (existingUser != null)
        {
            return Conflict(new { Message = "El nombre de usuario ya se encuentra registrado." });
        }

        // 3. Crear el modelo de dominio y encriptar contraseña con BCrypt
        var hash = BCrypt.Net.BCrypt.HashPassword(request.Password, workFactor: 11);

        var usuario = new Usuario
        {
            Username = request.Username.Trim().ToLower(),
            PasswordHash = hash,
            NombreCompleto = request.NombreCompleto.Trim(),
            Email = request.Email.Trim().ToLower(),
            Rol = request.Rol,
            Activo = true
        };

        // 4. Persistir en base de datos
        bool creado = await _userRepository.CreateAsync(usuario);

        if (!creado)
        {
            return StatusCode(StatusCodes.Status500InternalServerError, new { Message = "No se pudo crear el usuario en la base de datos." });
        }

        return CreatedAtAction(nameof(GetById), new { id = usuario.Id }, new UserResponse
        {
            Id = usuario.Id,
            Username = usuario.Username,
            NombreCompleto = usuario.NombreCompleto,
            Email = usuario.Email,
            Rol = usuario.Rol,
            Activo = usuario.Activo,
            FechaCreacion = usuario.FechaCreacion
        });
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateUserRequest request)
    {
        // 1. Validar solicitud
        var validationResult = await _updateUserValidator.ValidateAsync(request);
        if (!validationResult.IsValid)
        {
            return BadRequest(new { Errors = validationResult.Errors.Select(e => e.ErrorMessage) });
        }

        // 2. Buscar usuario existente
        var usuario = await _userRepository.GetByIdAsync(id);
        if (usuario == null)
        {
            return NotFound(new { Message = "El usuario solicitado no existe." });
        }

        // Evitar que el administrador se desactive a sí mismo por accidente
        var activeUserId = Guid.Parse(User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? Guid.Empty.ToString());
        if (id == activeUserId && !request.Activo)
        {
            return BadRequest(new { Message = "Por razones de seguridad, no puede desactivar su propio usuario administrador." });
        }

        // 3. Actualizar campos
        usuario.NombreCompleto = request.NombreCompleto.Trim();
        usuario.Email = request.Email.Trim().ToLower();
        usuario.Rol = request.Rol;
        usuario.Activo = request.Activo;

        // Si se proveyó una nueva contraseña, la hasheamos y actualizamos
        if (!string.IsNullOrEmpty(request.Password))
        {
            usuario.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password, workFactor: 11);
        }

        // 4. Guardar cambios
        bool actualizado = await _userRepository.UpdateAsync(usuario);

        if (!actualizado)
        {
            return StatusCode(StatusCodes.Status500InternalServerError, new { Message = "No se pudieron persistir los cambios del usuario." });
        }

        return Ok(new UserResponse
        {
            Id = usuario.Id,
            Username = usuario.Username,
            NombreCompleto = usuario.NombreCompleto,
            Email = usuario.Email,
            Rol = usuario.Rol,
            Activo = usuario.Activo,
            FechaCreacion = usuario.FechaCreacion
        });
    }
}
