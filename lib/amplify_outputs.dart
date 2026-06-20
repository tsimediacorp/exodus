const amplifyConfig = r'''{
  "auth": {
    "user_pool_id": "us-east-1_4n7wR1LTu",
    "aws_region": "us-east-1",
    "user_pool_client_id": "kdd43fnmmcldblgacu7l7s1so",
    "identity_pool_id": "us-east-1:21affb2d-d581-447d-8f54-3846ba3cbc0d",
    "mfa_methods": [],
    "standard_required_attributes": [
      "email"
    ],
    "username_attributes": [
      "email"
    ],
    "user_verification_types": [
      "email"
    ],
    "groups": [],
    "mfa_configuration": "NONE",
    "password_policy": {
      "min_length": 8,
      "require_lowercase": true,
      "require_numbers": true,
      "require_symbols": true,
      "require_uppercase": true
    },
    "unauthenticated_identities_enabled": true
  },
  "data": {
    "url": "https://in3vs7dcujfdxm6z2mhvwojxdu.appsync-api.us-east-1.amazonaws.com/graphql",
    "aws_region": "us-east-1",
    "default_authorization_type": "AMAZON_COGNITO_USER_POOLS",
    "authorization_types": [
      "AWS_IAM"
    ],
    "model_introspection": {
      "version": 1,
      "models": {
        "UserProfile": {
          "name": "UserProfile",
          "fields": {
            "id": {
              "name": "id",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "displayName": {
              "name": "displayName",
              "isArray": false,
              "type": "String",
              "isRequired": false,
              "attributes": []
            },
            "email": {
              "name": "email",
              "isArray": false,
              "type": "String",
              "isRequired": false,
              "attributes": []
            },
            "coupleId": {
              "name": "coupleId",
              "isArray": false,
              "type": "String",
              "isRequired": false,
              "attributes": []
            },
            "createdAt": {
              "name": "createdAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            },
            "updatedAt": {
              "name": "updatedAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            }
          },
          "syncable": true,
          "pluralName": "UserProfiles",
          "attributes": [
            {
              "type": "model",
              "properties": {}
            },
            {
              "type": "auth",
              "properties": {
                "rules": [
                  {
                    "provider": "userPools",
                    "ownerField": "owner",
                    "allow": "owner",
                    "identityClaim": "cognito:username",
                    "operations": [
                      "create",
                      "update",
                      "delete",
                      "read"
                    ]
                  }
                ]
              }
            }
          ],
          "primaryKeyInfo": {
            "isCustomPrimaryKey": false,
            "primaryKeyFieldName": "id",
            "sortKeyFieldNames": []
          }
        },
        "Couple": {
          "name": "Couple",
          "fields": {
            "id": {
              "name": "id",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "member1Id": {
              "name": "member1Id",
              "isArray": false,
              "type": "String",
              "isRequired": true,
              "attributes": []
            },
            "member2Id": {
              "name": "member2Id",
              "isArray": false,
              "type": "String",
              "isRequired": false,
              "attributes": []
            },
            "inviteCode": {
              "name": "inviteCode",
              "isArray": false,
              "type": "String",
              "isRequired": false,
              "attributes": []
            },
            "members": {
              "name": "members",
              "isArray": true,
              "type": "String",
              "isRequired": false,
              "attributes": [],
              "isArrayNullable": true
            },
            "messages": {
              "name": "messages",
              "isArray": true,
              "type": {
                "model": "Message"
              },
              "isRequired": false,
              "attributes": [],
              "isArrayNullable": true,
              "association": {
                "connectionType": "HAS_MANY",
                "associatedWith": [
                  "coupleId"
                ]
              }
            },
            "createdAt": {
              "name": "createdAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            },
            "updatedAt": {
              "name": "updatedAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            }
          },
          "syncable": true,
          "pluralName": "Couples",
          "attributes": [
            {
              "type": "model",
              "properties": {}
            },
            {
              "type": "auth",
              "properties": {
                "rules": [
                  {
                    "provider": "userPools",
                    "ownerField": "members",
                    "allow": "owner",
                    "identityClaim": "cognito:username",
                    "operations": [
                      "create",
                      "update",
                      "delete",
                      "read"
                    ]
                  },
                  {
                    "provider": "userPools",
                    "ownerField": "owner",
                    "allow": "owner",
                    "identityClaim": "cognito:username",
                    "operations": [
                      "create",
                      "update",
                      "delete",
                      "read"
                    ]
                  }
                ]
              }
            }
          ],
          "primaryKeyInfo": {
            "isCustomPrimaryKey": false,
            "primaryKeyFieldName": "id",
            "sortKeyFieldNames": []
          }
        },
        "Message": {
          "name": "Message",
          "fields": {
            "id": {
              "name": "id",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "coupleId": {
              "name": "coupleId",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "couple": {
              "name": "couple",
              "isArray": false,
              "type": {
                "model": "Couple"
              },
              "isRequired": false,
              "attributes": [],
              "association": {
                "connectionType": "BELONGS_TO",
                "targetNames": [
                  "coupleId"
                ]
              }
            },
            "authorId": {
              "name": "authorId",
              "isArray": false,
              "type": "String",
              "isRequired": true,
              "attributes": []
            },
            "role": {
              "name": "role",
              "isArray": false,
              "type": {
                "enum": "MessageRole"
              },
              "isRequired": false,
              "attributes": []
            },
            "text": {
              "name": "text",
              "isArray": false,
              "type": "String",
              "isRequired": true,
              "attributes": []
            },
            "visibility": {
              "name": "visibility",
              "isArray": false,
              "type": {
                "enum": "MessageVisibility"
              },
              "isRequired": false,
              "attributes": []
            },
            "members": {
              "name": "members",
              "isArray": true,
              "type": "String",
              "isRequired": false,
              "attributes": [],
              "isArrayNullable": true
            },
            "createdAt": {
              "name": "createdAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            },
            "updatedAt": {
              "name": "updatedAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            }
          },
          "syncable": true,
          "pluralName": "Messages",
          "attributes": [
            {
              "type": "model",
              "properties": {}
            },
            {
              "type": "auth",
              "properties": {
                "rules": [
                  {
                    "provider": "userPools",
                    "ownerField": "members",
                    "allow": "owner",
                    "identityClaim": "cognito:username",
                    "operations": [
                      "create",
                      "update",
                      "delete",
                      "read"
                    ]
                  }
                ]
              }
            }
          ],
          "primaryKeyInfo": {
            "isCustomPrimaryKey": false,
            "primaryKeyFieldName": "id",
            "sortKeyFieldNames": []
          }
        },
        "QuizRound": {
          "name": "QuizRound",
          "fields": {
            "id": {
              "name": "id",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "coupleId": {
              "name": "coupleId",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "day": {
              "name": "day",
              "isArray": false,
              "type": "AWSDate",
              "isRequired": true,
              "attributes": []
            },
            "prompt": {
              "name": "prompt",
              "isArray": false,
              "type": "String",
              "isRequired": true,
              "attributes": []
            },
            "members": {
              "name": "members",
              "isArray": true,
              "type": "String",
              "isRequired": false,
              "attributes": [],
              "isArrayNullable": true
            },
            "answers": {
              "name": "answers",
              "isArray": true,
              "type": {
                "model": "QuizAnswer"
              },
              "isRequired": false,
              "attributes": [],
              "isArrayNullable": true,
              "association": {
                "connectionType": "HAS_MANY",
                "associatedWith": [
                  "roundId"
                ]
              }
            },
            "createdAt": {
              "name": "createdAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            },
            "updatedAt": {
              "name": "updatedAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            }
          },
          "syncable": true,
          "pluralName": "QuizRounds",
          "attributes": [
            {
              "type": "model",
              "properties": {}
            },
            {
              "type": "auth",
              "properties": {
                "rules": [
                  {
                    "provider": "userPools",
                    "ownerField": "members",
                    "allow": "owner",
                    "identityClaim": "cognito:username",
                    "operations": [
                      "create",
                      "update",
                      "delete",
                      "read"
                    ]
                  }
                ]
              }
            }
          ],
          "primaryKeyInfo": {
            "isCustomPrimaryKey": false,
            "primaryKeyFieldName": "id",
            "sortKeyFieldNames": []
          }
        },
        "QuizAnswer": {
          "name": "QuizAnswer",
          "fields": {
            "id": {
              "name": "id",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "roundId": {
              "name": "roundId",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "round": {
              "name": "round",
              "isArray": false,
              "type": {
                "model": "QuizRound"
              },
              "isRequired": false,
              "attributes": [],
              "association": {
                "connectionType": "BELONGS_TO",
                "targetNames": [
                  "roundId"
                ]
              }
            },
            "authorId": {
              "name": "authorId",
              "isArray": false,
              "type": "String",
              "isRequired": true,
              "attributes": []
            },
            "answer": {
              "name": "answer",
              "isArray": false,
              "type": "String",
              "isRequired": true,
              "attributes": []
            },
            "members": {
              "name": "members",
              "isArray": true,
              "type": "String",
              "isRequired": false,
              "attributes": [],
              "isArrayNullable": true
            },
            "createdAt": {
              "name": "createdAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            },
            "updatedAt": {
              "name": "updatedAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            }
          },
          "syncable": true,
          "pluralName": "QuizAnswers",
          "attributes": [
            {
              "type": "model",
              "properties": {}
            },
            {
              "type": "auth",
              "properties": {
                "rules": [
                  {
                    "provider": "userPools",
                    "ownerField": "members",
                    "allow": "owner",
                    "identityClaim": "cognito:username",
                    "operations": [
                      "create",
                      "update",
                      "delete",
                      "read"
                    ]
                  }
                ]
              }
            }
          ],
          "primaryKeyInfo": {
            "isCustomPrimaryKey": false,
            "primaryKeyFieldName": "id",
            "sortKeyFieldNames": []
          }
        },
        "DailyAlignment": {
          "name": "DailyAlignment",
          "fields": {
            "id": {
              "name": "id",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "coupleId": {
              "name": "coupleId",
              "isArray": false,
              "type": "ID",
              "isRequired": true,
              "attributes": []
            },
            "day": {
              "name": "day",
              "isArray": false,
              "type": "AWSDate",
              "isRequired": true,
              "attributes": []
            },
            "score": {
              "name": "score",
              "isArray": false,
              "type": "Int",
              "isRequired": true,
              "attributes": []
            },
            "recap": {
              "name": "recap",
              "isArray": false,
              "type": "String",
              "isRequired": false,
              "attributes": []
            },
            "members": {
              "name": "members",
              "isArray": true,
              "type": "String",
              "isRequired": false,
              "attributes": [],
              "isArrayNullable": true
            },
            "createdAt": {
              "name": "createdAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            },
            "updatedAt": {
              "name": "updatedAt",
              "isArray": false,
              "type": "AWSDateTime",
              "isRequired": false,
              "attributes": [],
              "isReadOnly": true
            }
          },
          "syncable": true,
          "pluralName": "DailyAlignments",
          "attributes": [
            {
              "type": "model",
              "properties": {}
            },
            {
              "type": "auth",
              "properties": {
                "rules": [
                  {
                    "provider": "userPools",
                    "ownerField": "members",
                    "allow": "owner",
                    "identityClaim": "cognito:username",
                    "operations": [
                      "create",
                      "update",
                      "delete",
                      "read"
                    ]
                  }
                ]
              }
            }
          ],
          "primaryKeyInfo": {
            "isCustomPrimaryKey": false,
            "primaryKeyFieldName": "id",
            "sortKeyFieldNames": []
          }
        }
      },
      "enums": {
        "MessageRole": {
          "name": "MessageRole",
          "values": [
            "user",
            "exodus"
          ]
        },
        "MessageVisibility": {
          "name": "MessageVisibility",
          "values": [
            "private",
            "shared"
          ]
        }
      },
      "nonModels": {},
      "mutations": {
        "askExodus": {
          "name": "askExodus",
          "isArray": false,
          "type": "String",
          "isRequired": false,
          "arguments": {
            "coupleId": {
              "name": "coupleId",
              "isArray": false,
              "type": "String",
              "isRequired": true
            },
            "text": {
              "name": "text",
              "isArray": false,
              "type": "String",
              "isRequired": true
            },
            "visibility": {
              "name": "visibility",
              "isArray": false,
              "type": "String",
              "isRequired": true
            }
          }
        }
      }
    }
  },
  "version": "1.4"
}''';