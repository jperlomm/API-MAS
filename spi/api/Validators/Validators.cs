using FluentValidation;
using SmiApi.DTOs;

namespace SmiApi.Validators;

public class LoginRequestValidator : AbstractValidator<LoginRequest>
{
    public LoginRequestValidator()
    {
        RuleFor(x => x.Username)
            .NotEmpty().WithMessage("El nombre de usuario es obligatorio.")
            .MaximumLength(50).WithMessage("El nombre de usuario no puede superar los 50 caracteres.");

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("La contraseña es obligatoria.");
    }
}

public class CreateUserRequestValidator : AbstractValidator<CreateUserRequest>
{
    public CreateUserRequestValidator()
    {
        RuleFor(x => x.Username)
            .NotEmpty().WithMessage("El nombre de usuario es obligatorio.")
            .MinimumLength(3).WithMessage("El nombre de usuario debe tener al menos 3 caracteres.")
            .MaximumLength(50).WithMessage("El nombre de usuario no puede superar los 50 caracteres.");

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("La contraseña es obligatoria.")
            .MinimumLength(6).WithMessage("La contraseña debe tener al menos 6 caracteres.");

        RuleFor(x => x.NombreCompleto)
            .NotEmpty().WithMessage("El nombre completo es obligatorio.")
            .MaximumLength(100).WithMessage("El nombre completo no puede superar los 100 caracteres.");

        RuleFor(x => x.Email)
            .NotEmpty().WithMessage("El correo electrónico es obligatorio.")
            .EmailAddress().WithMessage("El correo electrónico no tiene un formato válido.")
            .MaximumLength(100).WithMessage("El correo electrónico no puede superar los 100 caracteres.");

        RuleFor(x => x.Rol)
            .NotEmpty().WithMessage("El rol es obligatorio.")
            .Must(rol => rol == "ADMIN" || rol == "OPERADOR" || rol == "TECNICO")
            .WithMessage("El rol provisto no es válido. Roles permitidos: ADMIN, OPERADOR, TECNICO.");
    }
}

public class UpdateUserRequestValidator : AbstractValidator<UpdateUserRequest>
{
    public UpdateUserRequestValidator()
    {
        RuleFor(x => x.NombreCompleto)
            .NotEmpty().WithMessage("El nombre completo es obligatorio.")
            .MaximumLength(100).WithMessage("El nombre completo no puede superar los 100 caracteres.");

        RuleFor(x => x.Email)
            .NotEmpty().WithMessage("El correo electrónico es obligatorio.")
            .EmailAddress().WithMessage("El correo electrónico no tiene un formato válido.")
            .MaximumLength(100).WithMessage("El correo electrónico no puede superar los 100 caracteres.");

        RuleFor(x => x.Rol)
            .NotEmpty().WithMessage("El rol es obligatorio.")
            .Must(rol => rol == "ADMIN" || rol == "OPERADOR" || rol == "TECNICO")
            .WithMessage("El rol provisto no es válido. Roles permitidos: ADMIN, OPERADOR, TECNICO.");

        RuleFor(x => x.Password)
            .MinimumLength(6).WithMessage("La contraseña debe tener al menos 6 caracteres si decide cambiarla.")
            .When(x => !string.IsNullOrEmpty(x.Password));
    }
}
