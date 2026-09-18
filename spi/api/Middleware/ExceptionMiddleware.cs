using System;
using System.Net;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;

namespace SmiApi.Middleware;

// Excepciones de negocio personalizadas para mapear a códigos HTTP específicos
public class SpiBusinessException : Exception
{
    public HttpStatusCode StatusCode { get; }

    public SpiBusinessException(string message, HttpStatusCode statusCode = HttpStatusCode.BadRequest) : base(message)
    {
        StatusCode = statusCode;
    }
}

public class ExceptionMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ExceptionMiddleware> _logger;

    public ExceptionMiddleware(RequestDelegate next, ILogger<ExceptionMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Ocurrió una excepción no controlada en la API.");
            await HandleExceptionAsync(context, ex);
        }
    }

    private static Task HandleExceptionAsync(HttpContext context, Exception exception)
    {
        context.Response.ContentType = "application/problem+json";
        
        var statusCode = HttpStatusCode.InternalServerError;
        var title = "Error Interno del Servidor";
        var detail = exception.Message;
        var errorType = "https://spi-network.net/errors/internal-server-error";

        if (exception is SpiBusinessException bizEx)
        {
            statusCode = bizEx.StatusCode;
            title = "Operación Inválida / Conflicto de Negocio";
            errorType = $"https://spi-network.net/errors/business-validation";
        }
        else if (exception is UnauthorizedAccessException)
        {
            statusCode = HttpStatusCode.Unauthorized;
            title = "No Autorizado";
            errorType = "https://spi-network.net/errors/unauthorized";
        }

        context.Response.StatusCode = (int)statusCode;

        var problemDetails = new
        {
            type = errorType,
            title = title,
            status = context.Response.StatusCode,
            detail = detail,
            instance = context.Request.Path.Value
        };

        var jsonOptions = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        return context.Response.WriteAsync(JsonSerializer.Serialize(problemDetails, jsonOptions));
    }
}
