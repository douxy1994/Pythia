module.exports.translate = async function translate(request, context) {
  const trimLines = context.config.trimLines !== "false";
  const collapseWhitespace = context.config.collapseWhitespace !== "false";
  let text = String(request.input.text || "").replace(/\r\n?/g, "\n");

  if (trimLines) {
    text = text.split("\n").map((line) => line.trim()).join("\n");
  }
  if (collapseWhitespace) {
    text = text.replace(/[\t ]+/g, " ").replace(/\n{3,}/g, "\n\n");
  }

  return {
    success: true,
    data: {
      text: text.trim()
    }
  };
};
