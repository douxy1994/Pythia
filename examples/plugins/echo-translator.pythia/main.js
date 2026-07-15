module.exports.translate = async function translate(request) {
  const { text, sourceLanguage, targetLanguage } = request.input;
  return {
    success: true,
    data: {
      text: `[${sourceLanguage}->${targetLanguage}] ${text}`
    }
  };
};
