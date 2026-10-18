from transformers import AutoModelForSequenceClassification, AutoTokenizer
MODEL = "distilbert/distilbert-base-uncased-finetuned-sst-2-english"
REVISION = "714eb0fa89d2f80546fda750413ed43d93601a13"
kwargs = {"revision": REVISION, "trust_remote_code": False}
AutoTokenizer.from_pretrained(MODEL, **kwargs).save_pretrained("/opt/model")
AutoModelForSequenceClassification.from_pretrained(
    MODEL, use_safetensors=True, **kwargs).save_pretrained("/opt/model")
