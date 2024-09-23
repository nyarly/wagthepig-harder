COPY public.users (id, email, encrypted_password, reset_password_token, reset_password_sent_at, remember_created_at, created_at, updated_at, name, bgg_username) FROM stdin;
1	nyarly@gmail.com	$2a$11$gT3FKUyQjPzOBbTbkSfLnuZ1JZ.mj0Pd7thksRqQxB7YU2bqs6t/G	ed81358039a333d337d92e3a0d39a0c992f854b095cc3664e87955f2bf98df7a	2019-10-11 06:12:12.928602	\N	2018-09-27 22:20:41.490675	2024-07-20 00:52:59.984963	Judson	nyarly
\.

SELECT pg_catalog.setval('public.users_id_seq', 3215, true);
