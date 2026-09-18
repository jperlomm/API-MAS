using System;

namespace SmiApi.Models;

public record KeaStatsSample(
    DateTime Timestamp,
    long Discover,
    long Request,
    long Ack,
    long Nak,
    long Drop
);
